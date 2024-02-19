function [ZoneInfo,CtrlSig]=callSim(HardwareTime,timestep,Meas)
%% Notes
%% Inputs
% timestep
%   User should put callSim function in a loop, where timestep=0:1:end
% Meas:
%     m_sup = Meas(1) :       discharge air mass flow rate [kg/s]
%     T_sup = Meas(2) :       discharge air temperature [°C]
%     w_sup = Meas(3) :       discharge air humidity ratio [kg/kg]
%     T_z = Meas(4) :         (emulated chamber) zone air temperature [°C]
%     w_z = Meas(5) :         (emulated chamber) zone humidity ratio [kg/kg]
%     T_out_emulated = Meas(6) :    emulated side outdoor air temperature for ASHP or outdoor water temperature for WSHP [°C]
%     Power_HVAC_electric = Meas(7);     Total electric power of HVAC system including primary/secondary system [kW]
% recv 
%   = 0; normal mode
%   = 1; recovery mode (also assign ts_recv in this case)
% ts_recv
%   The timestep to recover to.
%   For example, if recv=1 and ts_recv=20, the simulation will not update
%   inputs to the DB when timestep<=20.
% coll_recv
%   The collection that the user wants to recover, name can be random if
%   recv = 0
%% Outputs
% ZoneInfo
% ={'T_out','Tdp_out','RH_out',...
%         'Qsen_z','Qlat_z','Tz_cspt','Tz_hspt','T_z','Tdp_z','w_z','RH_z','w_out','T_w'};
%   T_out: Outdoor air temperature [C]
%   Tdp_out: Outdoor air dewpoint temperature [C]
%   RH_out: Outdoor air relative humidity [%]
%   Qsen_z: Sensible load [W], positive = heating, negative = cooling
%   Qlat_z: Latent load [W], positive = humidify, negative = dehumidify
%   Tz_cspt: Zone cooling setpoint [C]
%   Tz_hspt: Zone heating setpoint [C]
%   T_z: (Simulated) Zone air temperature [C]
%   Tdp_z: Zone dewpoint temperature [C]
%   w_z: Zone humidity ratio [kgwater/kgair]
%   RH_z: Zone relative humidity [%]
%   w_out: Outdoor air humidty ration [kgwater/kgair]
%   T_w: Groundwater temperature [C]
% CtrlSig
%   CtrlSig(1,1:2)
%     Only use the CtrlSig(2,i) value when CtrlSig(1,i)==1.
%   CtrlSig(2,1:2) = [sys_status,modulate_PID]
%     sys_status:       system status (0-off,1-on)
%     modulate_PID:     Activate modulate PID (0-off,1-on)
%% Others
% startTime
%   EPlus simulation start time in seconds
%   For example, if user wants to simulate nth day of the year, 
%   startTime = 86400*(n-1)
% stopTime
%   End time of the EPlus simulation. 
%   For example, if user wants to simulate nth day of the year, 
%   startTime = 86400*n
% stepsize
%   step size of each timestep (in seconds)
%   use to determine the associate time stamp
% GEB_step
%   number of timesteps between two GEB calls
% conn
%   DB connection cursor
% CollName
%   DB collection name. Automatic generated. Name constructed by the folder
%   names of the current and the upper two diectories, and date/time.
% ***Label
%   Label names for the data in DB
% timestep_GEB_start
%   timestep to start GEB computation
% timestep_GEB_read
%   timestep to read supervisory signals computed earlier

%% global variable
persistent recv ts_recv coll_recv startTime stopTime 
persistent stepsize 
persistent conn CollName DBName MeasLabel ZoneInfoLabel CtrlSigLabel ZIFields CSFields
persistent GEB_case Control_method TES Location STD Dense_Occupancy EGRSave_Occupant Season_type SimulinkName
%% Initialization
if timestep==0
    % delete any existing parallel pool
    poolobj = gcp('nocreate');
    delete(poolobj);
    % read settings from file
    settings=readtable('settings.csv');
    recv = settings.recv(1);   % recovery mode
    ts_recv = settings.ts_recv(1); % time step to recover to
    coll_recv = settings.coll_recv{1}; % collection to recover
    if (recv>0.5 && strcmp(coll_recv,'current'))  % if current, use the COLL in DBLoc.mat
        coll_recv=load('DBLoc.mat').CollName;
    end
    % Test Location (1-Atlanta;2-Buffalo;3-NewYork;4-Tucson;5-ElPaso)
    Location = settings.Location(1);
    % Season type (1-typical winter;2-typical should;3-extreme summer;4-typical summer)
    Season_type = settings.SeasonType(1);
    % Based on location and simulated season type, determine simulation
    % time (day of year)
    DOY_Table=[28 119 189 238; 365 71 197 183; 30 289 191 177; 2 280 228 240; 9 107 170 203];
    DOY = DOY_Table(Location,Season_type);  % day of year
    startTime_forEnergyPlus=86400*(DOY-2);   % EPlus simulation start time in seconds
    startTime=86400*(DOY-1);                 % MongoDB and ControlModel start time in seconds
    stopTime=86400*DOY;     % EPlus simulation end time in seconds
    % GEB scenario to be tested (0-none,1-eff,2-shed,3-shift,4-modulate)
    GEB_case = settings.GEB_case(1); 
    % GEB control method (0-rule based, 1-MPC)
    Control_method = settings.Control_method(1);
    % Test TES or not (0-no, 1-yes) 
    % (For small office, is test TES case, use the VB with PCM wall)
    TES = settings.TES(1);
    % STD (1-STD2004;2-STD2019)
    STD = settings.STD(1); 
    % Dense occupancy or not
    Dense_Occupancy= settings.occ_dense(1);
    % Energy-saving occupants or not
    EGRSave_Occupant= settings.occ_energysaving(1);
    % parameters
    stepsize=settings.stepsize(1);    % step size of each timestep (in seconds)
    % directory
    par_dir = fileparts(strcat(pwd,'\callSim.m'));
    % add OBMsubfuntion to path
    addpath(strcat(par_dir,'\OBM'));
    % add Airflow ANN model to path
    addpath(strcat(par_dir,'\OBM\AirflowANNmodel'));
    % add DB function to path
    addpath(strcat(par_dir,'\DB'));
    % add virtual building to path
    addpath(strcat(par_dir,'\VB'));
    % add control models to path
    addpath(strcat(par_dir,'\CTRL'));
    % database name
    DBName = 'HILFT';
    % connect to the database (make sure the DB is created first)
    conn = mongo('localhost',27017,DBName);
    % collection name
    CollName_Location={'Atlanta';'Buffalo';'NewYork';'Tucson';'ElPaso'};
    CollName_GEBCase={'None';'Eff';'Shed';'Shif';'Modu'};
    CollName_Season={'TypWin';'TypShou';'ExtrmSum';'TypSum'};
    CollName_GEBControl={'RB';'MPC'};
    CollName_STD={'2004';'2019'};
    CollName_DenOcc={'TypOcc';'DenOcc'};
    CollName_EGROcc={'TypBehav';'EGRBehav'};
    CollName_TES={'NoTES';'TES'};
%     parts=strsplit(par_dir, '\');
%     CollName=[char(parts(end)),'_',char(datestr(now,'mmddyyyy')),...
%         '_',char(datestr(now,'HHMMSS'))];
    CollName=[char(CollName_Location(Location)),...
        '_',char(CollName_GEBCase(GEB_case+1)),'_',char( CollName_Season(Season_type)),'_',...
        char(CollName_GEBControl(Control_method+1)),'_',char(CollName_STD(STD)),'_',...
        char(CollName_DenOcc(Dense_Occupancy+1)),'_',char(CollName_EGROcc(EGRSave_Occupant+1)),...
        '_',char(CollName_TES(TES+1)),'_',...
        char(datestr(now,'mmddyyyy')),'_',char(datestr(now,'HHMMSS'))];
    % recovery of an existing collection
    if (recv>0.5) 
        CollName=coll_recv;
    end
    % save DBName and CollName to share with other models
    save DBLoc.mat DBName CollName
    % Labels
    MeasLabel={'m_sup','T_sup','w_sup','T_z','w_z','T_out_emulated','Power_HVAC'};
    ZoneInfoLabel={'T_out','Tdp_out','RH_out',...
        'Qsen_z','Qlat_z','Tz_cspt','Tz_hspt','T_z','Tdp_z','w_z','RH_z','w_out','T_w'};
    CtrlSigLabel={'sys_status','Tz_cspt','Tz_hspt'};
    CSFields=label2mongofield_find(CtrlSigLabel);
    ZIFields=label2mongofield_find(ZoneInfoLabel);
    if (recv<0.5) % start a new collection in normal mode
        % create collection
        if any(strcmp(CollName,conn.CollectionNames))
            % drop the old collection
            dropCollection(conn,CollName);
        end
        createCollection(conn,CollName);
    end
    % insert recovery settings to DB
    remove(conn,CollName,'{"DocType":"RecvSettings"}');
    RecvDoc.DocType="RecvSettings";
    RecvDoc.recv=recv;
    RecvDoc.time_recv=startTime+ts_recv*60;
    insert(conn,CollName,RecvDoc);
end
%% Push data to DB 
if (recv<0.5 || timestep>ts_recv)
    % remove all existing doc for the current timestep in recovery mode
    if (recv>0.5)
        remove(conn,CollName,['{"Timestep":',num2str(timestep),'}']);
    end
    % create doc for crucial simulated data 
    DataDoc.DocType='SimData';
    DataDoc.Timestep=timestep;
    DataDoc.Time=startTime+timestep*60;
    insert(conn,CollName,DataDoc);
    % push Meas to DB
    MeasDoc.DocType='Measurements';
    MeasDoc.HardwareTime = HardwareTime;
    MeasDoc.Timestep=timestep;
    MeasDoc.Time=startTime+timestep*60;
    insert(conn,CollName,MeasDoc);    
    Mquery=mongo2mongofiled_upset(MeasLabel,...
        Meas);
    update(conn,CollName,['{"Timestep":',num2str(timestep),...
        ',"DocType":"Measurements"}'],Mquery);
    % run GEB control module
    CtrlSig = Control_Model(startTime,timestep,Season_type,GEB_case,Control_method,TES,Meas,STD,Dense_Occupancy,conn,CollName);
else
    % Get CtrlSig from DB in recovery mode
    CtrlSig=zeros(2,length(CtrlSigLabel));
    ret_CS=find(conn,CollName,'Query',['{"Timestep":',num2str(timestep),...
        ',"DocType":"SupvCtrlSig"}'],'Projection',CSFields);
    for i=1:length(CtrlSigLabel)
        CtrlSig(:,i)=ret_CS.(char(CtrlSigLabel(i)));
    end
end
%% run virtual building model
if timestep==0
    % open Simulink
    % Simulink file name
    if Location==4  % Tucson
        if Season_type==1 || Season_type==4
            SimulinkName=['OneZone_STD',char(CollName_STD(STD)),'_',...
                char(CollName_Location(Location)),'2019Year_',char(CollName_DenOcc(Dense_Occupancy+1)),'.slx'];
        elseif Season_type==2
            SimulinkName=['OneZone_STD',char(CollName_STD(STD)),'_',...
                char(CollName_Location(Location)),'2015Year_',char(CollName_DenOcc(Dense_Occupancy+1)),'.slx'];
        elseif Season_type==3
            SimulinkName=['OneZone_STD',char(CollName_STD(STD)),'_',...
                char(CollName_Location(Location)),'2017Year_',char(CollName_DenOcc(Dense_Occupancy+1)),'.slx'];
        end
    elseif Location==5  % ElPaso
        if Season_type==4
            SimulinkName=['OneZone_STD',char(CollName_STD(STD)),'_',...
                char(CollName_Location(Location)),'2015Year_',char(CollName_DenOcc(Dense_Occupancy+1)),'.slx'];
        else
            SimulinkName=['OneZone_STD',char(CollName_STD(STD)),'_',...
                char(CollName_Location(Location)),'2013Year_',char(CollName_DenOcc(Dense_Occupancy+1)),'.slx'];
        end
    else
        SimulinkName=['OneZone_STD',char(CollName_STD(STD)),'_',...
            char(CollName_Location(Location)),'_',char(CollName_DenOcc(Dense_Occupancy+1)),'.slx'];
    end
    open_system(SimulinkName);
    % set Simulink start time and stop time at the initial call
    set_param(bdroot,'StartTime',string(startTime_forEnergyPlus),'StopTime',string(stopTime));
    % start Simulink
    set_param(bdroot,'SimulationCommand','start');
    for i_firstday=0:(1440-1)
        set_param(bdroot,'SimulationCommand','pause');
        set_param(bdroot,'SimulationCommand','continue');
    end  
else
    % continue Simulink
    set_param(bdroot,'SimulationCommand','continue');
end
% pause Simulink
set_param(bdroot,'SimulationCommand','pause');
%% Get ZoneInfo from DB
ZoneInfo=zeros(1,length(ZoneInfoLabel));
ret=find(conn,CollName,'Query',['{"Timestep":',num2str(timestep),...
    ',"DocType":"SimData"}'],'Projection',ZIFields);
for i=1:length(ZoneInfoLabel)
    ZoneInfo(i)=ret.(char(ZoneInfoLabel(i)));
end
%% Finalization
if (timestep==86400/stepsize)
    set_param(bdroot,'SimulationCommand','stop');
    save_system(SimulinkName);
    close_system(SimulinkName);
    poolobj = gcp('nocreate');
    delete(poolobj);
end
end
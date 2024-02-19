function CtrlSig = Control_Model(startTime,timestep,Season_type,GEB_case,Control_method,TES,Meas,STD,Dense_Occupancy,conn,CollName)
%% inputs
% startTime:start time in seconds of the tested DOY
% timestep: current timestep
% Season_type: used to determine whether daylight saving (1-typical winter;2-typical shoulder;3-extreme summer;4-typical summer)
% TES: whether to test ice tank (0-no, 1-yes)
% GEB_case: GEB scenario to be tested (0-none,1-eff,2-shed,3-shift,4-modulate)
% GEB_control: GEB control method (0-rule based, 1-MPC)
% STD: building code standard (1-STD2004;2-STD2019)
% Dense_Occupancy: 0-typical occupancy; 1-dense occupancy
% conn: database connection cursor
% CollName: database collection name
% Meas:
%     m_sup = Meas(1) :       discharge air mass flow rate [kg/s]
%     T_sup = Meas(2) :       discharge air temperature [°C]
%     w_sup = Meas(3) :       discharge air humidity ratio [kg/kg]
%     T_z = Meas(4) :         (emulated chamber) zone air temperature [°C]
%     w_z = Meas(5) :         (emulated chamber) zone humidity ratio [kg/kg]
%     T_out_emulated = Meas(6) :    emulated side outdoor air temperature for ASHP or outdoor water temperature for WSHP [°C]
%     Power_HVAC_electric = Meas(7);     Total electric power of HVAC system including primary/secondary system [kW]
%% outputs
% CtrlSig(1,1:2)
%     Take the CtrlSig(2,i) setpoint only when CtrlSig(1,i)==1
% CtrlSig(2,1:2) = [sys_status,modulate_PID]
%     sys_status:       system status (0-off,1-on)
%     modulate_PID:     Activate modulate PID (0-off,1-on)
%% Main program
%% read measurements
% zone-level measurements
m_sup = Meas(1);
T_sup = Meas(2);
w_sup = Meas(3);
T_z = Meas(4);
w_z = Meas(5);
% emulated outdoor air/water temperature
T_out_emulated = Meas(6);
%% persistent TOU structure
persistent PeakPeriod CollNmae_sparate Location Location_Num ShiftSche
%% determine whether daylight saving
% Occupancy period is from 6:00 to 22:00 (standard time)
OccupiedPeriod=[6*60 22*60];
if Season_type==1 % typical winter, no daylight saving. clock time=standard time
    OccupiedPeriod=OccupiedPeriod;
    DaylightSaving=0;
%     OccTimestep=timestep;
else % for other test date, it is winin daylight saving period, clok time=standard time - 60min
    OccupiedPeriod=OccupiedPeriod-60;
    DaylightSaving=1;
%     OccTimestep=timestep+60;   % OccTimesetp is used to locate the occupant schedule.
%     if OccTimestep>1440
%         OccTimestep=OccTimestep-1440;
%     end
end
%% determine system operation
% system operation hour is the same as occupied hour
if (timestep>(OccupiedPeriod(1))) && (timestep<=(OccupiedPeriod(2)))
    sys_status = 1;
else
    sys_status = 0;
end
% determine whether occupied 
if (timestep>OccupiedPeriod(1)) && (timestep<=OccupiedPeriod(2))
    Occupied = 1;
else
    Occupied = 0;
end
%% set to default setpoint 
[Tz_hspt,Tz_cspt]=DefaultSettingHP(sys_status,Season_type,Occupied);
%% initialized the peak period for four location and three seasons
if isempty(PeakPeriod)
    PeakPeriod=cell(4,4);
    PeakPeriod{1,1}=[99 99];  % Atlanta typical winter
    PeakPeriod{1,2}=[99 99];  % Atlanta typical shoulder
    PeakPeriod{1,3}=[14 19];  % Atlanta extreme summer
    PeakPeriod{1,4}=[14 19];  % Atlanta typical summer
    PeakPeriod{2,1}=[17 20];
    PeakPeriod{2,2}=[99 99];
    PeakPeriod{2,3}=[11 17];
    PeakPeriod{2,4}=[11 17];
    PeakPeriod{3,1}=[12 20];
    PeakPeriod{3,2}=[12 20];
    PeakPeriod{3,3}=[12 20];
    PeakPeriod{3,4}=[12 20];
    PeakPeriod{4,1}=[6 10 17 21];
    PeakPeriod{4,2}=[6 10 17 21];
    PeakPeriod{4,3}=[14 20];
    PeakPeriod{4,4}=[14 20];
    
    ShiftSche=cell(4,4);
    ShiftSche{1,1}=[0 0]; % Atlanta typical winter
    ShiftSche{1,2}=[0 0]; % Atlanta typical shoulder
    ShiftSche{1,3}=[1 1]; % Atlanta extreme summer
    ShiftSche{1,4}=[2 1]; % Atlanta typical summer (the dT of precooling/heating, the duration)
    ShiftSche{2,1}=[0 0];
    ShiftSche{2,2}=[0 0];
    ShiftSche{2,3}=[0 0];
    ShiftSche{2,4}=[0 0];
    ShiftSche{3,1}=[0 0];
    ShiftSche{3,2}=[4 2];
    ShiftSche{3,3}=[4 1];
    ShiftSche{3,4}=[4 1];
    ShiftSche{4,1}=[0 0];
    ShiftSche{4,2}=[1 1];
    ShiftSche{4,3}=[1 1];
    ShiftSche{4,4}=[1 1];

    CollNmae_sparate=strsplit(CollName,'_');
    Location=CollNmae_sparate{1};
    if strcmp(Location,'Atlanta')
        Location_Num=1;
    elseif strcmp(Location,'Buffalo')
        Location_Num=2;
    elseif strcmp(Location,'NewYork')
        Location_Num=3;
    elseif strcmp(Location,'Tucson')
        Location_Num=4;
    end
end
%% determine setpoints
% initialized vav mass flow rate setpoints. will only be used when
% GEB_control==1 (MPC mode)
m_sp = 0;
if Season_type==1   % winter case, reset the heating setpoint
    switch Control_method
        case 0  % Rule-based control
            % determine zone-level setpoints
            %!!!!!!!!!! need to be modified after utility programs are decided
            modulate_PID = 0;
            if (GEB_case>0) % for all GEB cases
                if sys_status==1
                    % GEB_case==1,2,3, use different zone temperature setpoint
                    if (GEB_case==1)
                        Tz_hspt = Tz_hspt;
                    elseif (GEB_case==2)
                        if Location_Num==4 
                            shed_start_1=(PeakPeriod{Location_Num,(Season_type)}(1)-DaylightSaving)*60;
                            shed_end_1=(PeakPeriod{Location_Num,(Season_type)}(2)-DaylightSaving)*60;
                            shed_start_2=(PeakPeriod{Location_Num,(Season_type)}(3)-DaylightSaving)*60;
                            shed_end_2=(PeakPeriod{Location_Num,(Season_type)}(4)-DaylightSaving)*60;
                            if (sys_status>0)
                                if (timestep>shed_start_1 && timestep<=shed_end_1) ||...
                                        (timestep>shed_start_2 && timestep<=shed_end_2)
                                    Tz_hspt = 66;
                                    Tz_cspt = 80;
                                end
                            end
                        else
                            shed_start=(PeakPeriod{Location_Num,(Season_type)}(1)-DaylightSaving)*60;
                            shed_end=(PeakPeriod{Location_Num,(Season_type)}(2)-DaylightSaving)*60;
                            if (sys_status>0)
                                if (timestep>shed_start && timestep<=shed_end)
                                    Tz_hspt = 66;
                                    Tz_cspt = 80;
                                end
                            end
                        end
                    elseif (GEB_case==3)
                        PL=ShiftSche{Location_Num,Season_type}(2);
                        PTSC=ShiftSche{Location_Num,Season_type}(1);
                        if Location_Num==4 
                            preheat_start=(PeakPeriod{Location_Num,(Season_type)}(3)-DaylightSaving-PL)*60;  % for Tucson TypWin case, only shift in second peak period
                            shed_start_1=(PeakPeriod{Location_Num,(Season_type)}(1)-DaylightSaving)*60;
                            shed_end_1=(PeakPeriod{Location_Num,(Season_type)}(2)-DaylightSaving)*60;
                            shed_start_2=(PeakPeriod{Location_Num,(Season_type)}(3)-DaylightSaving)*60;
                            shed_end_2=(PeakPeriod{Location_Num,(Season_type)}(4)-DaylightSaving)*60;
                            if (sys_status>0)
                                if (timestep>shed_start_1 && timestep<=shed_end_1) ||...
                                        (timestep>shed_start_2 && timestep<=shed_end_2)
                                    Tz_hspt = 66;
                                elseif (timestep>preheat_start && timestep<=shed_start_2)
                                    Tz_hspt = Tz_hspt+PTSC;
                                end
                            end
                        else
                            preheat_start=(PeakPeriod{Location_Num,(Season_type)}(1)-DaylightSaving-PL)*60;
                            shed_start=(PeakPeriod{Location_Num,(Season_type)}(1)-DaylightSaving)*60;
                            shed_end=(PeakPeriod{Location_Num,(Season_type)}(2)-DaylightSaving)*60;
                            if (sys_status>0)
                                if (timestep>shed_start && timestep<=shed_end)
                                    Tz_hspt = 66;
                                elseif (timestep>preheat_start && timestep<=shed_start)
                                    Tz_hspt = Tz_hspt+PTSC;
                                end
                            end
                        end
                    elseif (GEB_case==4)
                        Tz_hspt = Tz_hspt;
                        modulate_PID = 1;   % activate modulate PID
                    end
                else
                    [Tz_hspt,Tz_cspt]=DefaultSettingHP(sys_status,Season_type,Occupied);
                end
            else
                [Tz_hspt,Tz_cspt]=DefaultSettingHP(sys_status,Season_type,Occupied);
            end
            % convert °F to °C
            Tz_cspt = (Tz_cspt-32)/1.8;
            Tz_hspt = (Tz_hspt-32)/1.8;
        case 1  % MPC control
    end
else    % for other case, reset cooling setpoint
    switch Control_method
        case 0  % Rule-based control
            % determine zone-level setpoints
            %!!!!!!!!!! need to be modified after utility programs are decided
            modulate_PID = 0;
            if (GEB_case>0) % for all GEB cases
                if sys_status==1
                    % GEB_case==1,2,3, use different zone temperature setpoint
                    if (GEB_case==1)
                        Tz_cspt = Tz_cspt;
                    elseif (GEB_case==2)
                        if Location_Num==4 && Season_type==2
                            shed_start_1=(PeakPeriod{Location_Num,(Season_type)}(1)-DaylightSaving)*60;
                            shed_end_1=(PeakPeriod{Location_Num,(Season_type)}(2)-DaylightSaving)*60;
                            shed_start_2=(PeakPeriod{Location_Num,(Season_type)}(3)-DaylightSaving)*60;
                            shed_end_2=(PeakPeriod{Location_Num,(Season_type)}(4)-DaylightSaving)*60;
                            if (sys_status>0)
                                if (timestep>shed_start_1 && timestep<=shed_end_1) ||...
                                        (timestep>shed_start_2 && timestep<=shed_end_2)
                                    Tz_hspt = 66;
                                    Tz_cspt = 80;
                                end
                            end
                        else
                            shed_start=(PeakPeriod{Location_Num,(Season_type)}(1)-DaylightSaving)*60;
                            shed_end=(PeakPeriod{Location_Num,(Season_type)}(2)-DaylightSaving)*60;
                            if (sys_status>0)
                                if (timestep>shed_start && timestep<=shed_end)
                                    Tz_hspt = 66;
                                    Tz_cspt = 80;
                                end
                            end
                        end
                    elseif (GEB_case==3)
                        PL=ShiftSche{Location_Num,Season_type}(2);
                        PTSC=ShiftSche{Location_Num,Season_type}(1);
                        if Location_Num==4 && Season_type==2
                            precool_start=(PeakPeriod{Location_Num,(Season_type)}(3)-DaylightSaving-PL)*60;  % for Tucson TypSholr case, only shift in second peak period
                            shed_start_1=(PeakPeriod{Location_Num,(Season_type)}(1)-DaylightSaving)*60;
                            shed_end_1=(PeakPeriod{Location_Num,(Season_type)}(2)-DaylightSaving)*60;
                            shed_start_2=(PeakPeriod{Location_Num,(Season_type)}(3)-DaylightSaving)*60;
                            shed_end_2=(PeakPeriod{Location_Num,(Season_type)}(4)-DaylightSaving)*60;
                            if (sys_status>0)
                                if (timestep>shed_start_1 && timestep<=shed_end_1) ||...
                                        (timestep>shed_start_2 && timestep<=shed_end_2)
                                    Tz_cspt = 80;
                                elseif (timestep>precool_start && timestep<=shed_start_2)
                                    Tz_cspt = Tz_cspt-PTSC;
                                end
                            end
                        else
                            precool_start=(PeakPeriod{Location_Num,(Season_type)}(1)-DaylightSaving-PL)*60;
                            shed_start=(PeakPeriod{Location_Num,(Season_type)}(1)-DaylightSaving)*60;
                            shed_end=(PeakPeriod{Location_Num,(Season_type)}(2)-DaylightSaving)*60;
                            if (sys_status>0)
                                if (timestep>shed_start && timestep<=shed_end)
                                    Tz_cspt = 80;
                                elseif (timestep>precool_start && timestep<=shed_start)
                                    Tz_cspt = Tz_cspt-PTSC;
                                end
                            end
                        end
                    elseif (GEB_case==4)
                        Tz_cspt = Tz_cspt;
                        modulate_PID = 1;   % activate modulate PID
                    end
                else
                    [Tz_hspt,Tz_cspt]=DefaultSettingHP(sys_status,Season_type,Occupied);
                end
            else
                [Tz_hspt,Tz_cspt]=DefaultSettingHP(sys_status,Season_type,Occupied);
            end
            % convert °F to °C
            Tz_cspt = (Tz_cspt-32)/1.8;
            Tz_hspt = (Tz_hspt-32)/1.8;
        case 1  % MPC control
    end
end
%% Outputs
CtrlSig(1,1:2) = [1,1];
if Control_method==1
    CtrlSig(1,1:2) = [1,1];
end
CtrlSig(2,1:2) = [sys_status,modulate_PID];

%% save control signals to MongoDB
    CtrlSigDoc.DocType = 'SupvCtrlSig';
    CtrlSigDoc.Timestep = timestep;
    CtrlSigDoc.Time = startTime+timestep*60;
    CtrlSigDoc.sys_status = CtrlSig(:,1);
    CtrlSigDoc.Tz_cspt = [1;Tz_cspt];
    CtrlSigDoc.Tz_hspt = [1;Tz_hspt];    
    insert(conn,CollName,CtrlSigDoc);  
end


clc,clear
% please fill the .mat file name, location and season
MatFileName=['Tucson_Shif_TypSum_RB_2004_TypOcc_TypBehav_NoTES_03252023_112617'];
load([MatFileName '.mat']);
%% Push data to DB
% database name
DBName = 'HILFT';
% connect to the database (make sure the DB is created first)
conn = mongo('localhost',27017,DBName);
CollName=[MatFileName];
save DBLoc.mat DBName CollName
%  create the collection
if any(strcmp(CollName,conn.CollectionNames))
    % drop the old collection
    dropCollection(conn,CollName);
end
createCollection(conn,CollName);
% delete 'x_id'
Measurements=rmfield(Measurements,'x_id');
SupvCtrlSig=rmfield(SupvCtrlSig,'x_id');
SimData=rmfield(SimData,'x_id');
OccupantMatrix=rmfield(OccupantMatrix,'x_id');
% push data to DB
insert(conn,CollName,Measurements);
insert(conn,CollName,SupvCtrlSig);
insert(conn,CollName,SimData);
insert(conn,CollName,OccupantMatrix);

% %% Generate hardware .csv file
% par_dir = fileparts(strcat(pwd,'\SaveMatToDB.m'));
% writetable(HardwareData.Buffalo_Eff_DenseOcc_220803a,...
%     strcat(par_dir,'\HardwareData\HardwareData.csv'),'Delimiter',',','QuoteStrings',true)
% 
% %% Modify the settings.csv file
% settings.recv(1)=1;
% settings.ts_recv(1)=1440;
% % filedata=readtable('settings.csv');
% % filedata.recv(1)=1;
% % filedata.ts_recv(1)=1440;
% writetable(settings,'settings.csv')

















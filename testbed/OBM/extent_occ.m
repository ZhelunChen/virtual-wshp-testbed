clc,clear
load('Fixed_OccupantMatrix_1.5_typ.mat')
Acc_filename = 'AcceptabilityRangeSummary.xlsx';
simsettingsrange = 'B10:I13';
[simsettings] = xlsread(Acc_filename, 1,simsettingsrange);


for occ=8:11
    Fixed_OccupantMatrix{1}(occ).Gender=simsettings(occ-7,1);
    Fixed_OccupantMatrix{1}(occ).AcceptabilityVector=[simsettings(occ-7,2:5),simsettings(occ-7,4:5),simsettings(occ-7,2:3)];
    for s = 1:4
        if median(Fixed_OccupantMatrix{1}(occ).AcceptabilityVector(...
                    ((s*2)-1)):1:...
                    Fixed_OccupantMatrix{1}(occ).AcceptabilityVector(s*2)) <= 0
                Fixed_OccupantMatrix{1}(occ).PreferenceClass(s) = 0;
            else
                Fixed_OccupantMatrix{1}(occ).PreferenceClass(s) = 1;
            end
    end
    Fixed_OccupantMatrix{1}(occ).PersonalConstraints(1,(1:3))=simsettings(occ-7,6:8);
    Fixed_OccupantMatrix{1}(occ).PersonalConstraints(2,(1:3))=[0.8 1 0.8];
end
save('Fixed_OccupantMatrix_1.5_typ.mat','Fixed_OccupantMatrix')
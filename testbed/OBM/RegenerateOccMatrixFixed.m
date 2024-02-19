clc, clear all
load('Fixed_OccupantMatrix_1_NGRSave.mat')
for z=1
    for occ=1:size(Fixed_OccupantMatrix{z},2)
%         Fixed_OccupantMatrix{z}(occ).OfficeType=6;
        Fixed_OccupantMatrix{z}(occ).PersonalConstraints(2,3)=0.9;
    end
end
save('Fixed_OccupantMatrix_1_NGRSave.mat','Fixed_OccupantMatrix')
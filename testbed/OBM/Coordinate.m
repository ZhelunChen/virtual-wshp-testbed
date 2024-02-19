function [Position] = Coordinate(OccupantMatrix,ENumInOcc,counter_occ)
Occ_Coordinate_set=zeros(11,2);
Occ_Coordinate_set=[6.9225,3.425;11.5375,3.425;20.7675,3.425;4.615,1.575;13.845,1.575;...
    23.075,1.575;24.875,1.575;16.1525,3.425;2.825,1.575;9.23,1.575;18.46,1.575];
Position = Occ_Coordinate_set((OccupantMatrix.OccupantNum),:);
end
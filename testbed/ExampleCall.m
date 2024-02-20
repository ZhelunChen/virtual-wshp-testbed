clc
clear all
%% Please provide the simulation time period
T = 86400; % length of the simulation period 
ntimestep=T/60; % total number of time step
for timestep=0:ntimestep
    %% At every iteration,update measurements
    HardwareTime = 0.0001*timestep; % Please assign a unique hardware clock time this variable. It can be an index number or the actual hardware time
    % Please refer to the notes in callSim for the meaning of each inputs
    Meas=[0.1,18,0.009,22,0.0095,28,300];
    %% Call Simulation
    [ZoneInfo,CtrlSig]=callSim(HardwareTime,timestep,Meas);
end

% save all data to .mat file
DataDL;
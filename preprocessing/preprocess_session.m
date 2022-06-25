
function preprocess_session(basepath,varargin)
% Function for processing electrophysiology data in the SNLab adapted from
% preprocessSession.m ayalab/neurocode repo
%
% Dependencies
%   - external packages: neurocode,KS2Wrapper
%   - schafferlab/github/Kilosort
%   - schafferlab/github/CellExplorer
%   - schafferlab/github/neurocode/utils
%
% Data organization assumptions
%   - Data should be organized with each recordding session saved within an animal folder i.e. 'animal_id/basename'
%   - 'basename' is used by CellExplorer and other buzcode functions.
%     Therefore, it is important to make this name unique.
%   - XML with channel mapping completed should be done and located in the
%     basepath.

% LBerkowitz 2021

p = inputParser;
addParameter(p,'analogInputs',false,@islogical);
addParameter(p,'analogChannels',[],@isnumeric);
addParameter(p,'digitalInputs',false,@islogical);
addParameter(p,'digitalChannels',[],@isnumeric);
addParameter(p,'getAcceleration',true,@islogical);
addParameter(p,'concatenateDat',false,@islogical);
addParameter(p,'getLFP',true,@islogical);
addParameter(p,'getEMG',true,@islogical);
addParameter(p,'stateScore',true,@islogical);
addParameter(p,'DLC',false,@islogical);
addParameter(p,'kilosort',false,@islogical);
addParameter(p,'removeNoise',false,@islogical);
addParameter(p,'ssd_path','C:\kilo_temp',@ischar);    % Path to SSD disk.
addParameter(p,'lfp_fs',1250,@isnumeric);
addParameter(p,'specialChannels',[30,59,17],@isnumeric) % default for ASYpoly2A64
addParameter(p,'acquisition_event_flag',false,@islogical) % if you have start and stop recording
% events else default uses first and last event as indicies for start and stop of recording
addParameter(p,'check_epochs',false,@islogical) % fixes bouncy events
addParameter(p,'maze_size',30,@isnumeric); % in cm


parse(p,varargin{:});

analogInputs = p.Results.analogInputs;
analogChannels = p.Results.analogChannels;
digitalInputs = p.Results.digitalInputs;
digitalChannels = p.Results.digitalChannels;
getAcceleration = p.Results.getAcceleration;
getLFP = p.Results.getLFP;
getEMG = p.Results.getEMG;
concatenateDat = p.Results.concatenateDat;
kilosort = p.Results.kilosort;

% cleanArtifacts = p.Results.cleanArtifacts;
stateScore = p.Results.stateScore;
DLC = p.Results.DLC;
removeNoise = p.Results.removeNoise;
ssd_path = p.Results.ssd_path;
lfp_fs = p.Results.lfp_fs;
specialChannels = p.Results.specialChannels;
acquisition_event_flag = p.Results.acquisition_event_flag;
check_epochs = p.Results.check_epochs;
maze_size = p.Results.maze_size;
% Prepare dat files and prepare metadata

% Set basename from folder
basename = basenameFromBasepath(basepath);

% If non-contiguous recordings were taken, merge the dat files into one
% session. Default is false.
if concatenateDat
    concatenateDats(basepath,0,1);
end


% rename amplifier.dat to basename.dat
if ~isempty(dir([basepath,filesep,'amplifier.dat']))
    disp(['renaming amplifer.dat to ',basename,'.dat'])
    % create command
    command = ['rename "',basepath,filesep,'amplifier.dat"',' ',basename,'.dat'];
    system(command); % run through system command prompt
end

% lets also rename the xml if present.
if ~isempty(dir([basepath,filesep,'amplifier.xml']))
    disp(['renaming amplifer.xml to ',basename,'.xml'])
    % create command
    command = ['rename "',basepath,filesep,'amplifier.xml"',' ',basename,'.xml'];
    system(command); % run through system command prompt
end

% Create SessionInfo
session = sessionTemplate(basepath,'showGUI',true);
% Process additional inputs

% Analog inputs
% check the two different fucntions for delaing with analog inputs and proably rename them
if analogInputs
    if  ~isempty(analogChannels)
        analogInp = computeAnalogInputs('analogCh',analogChannels,'saveMat',true,'fs',session.extracellular.sr);
    else
        analogInp = computeAnalogInputs('analogCh',[],'saveMat',true,'fs',session.extracellular.sr);
    end
    
    % analog pulses ...
    [pulses] = getAnalogPulses('samplingRate',session.extracellular.sr);
end

% Digital inputs
if digitalInputs
    if ~isempty(digitalChannels)
        % need to change to only include specified channels
        digitalInp = getDigitalIn('all','filename',"digitalin.dat",'fs',session.extracellular.sr);
    else
        digitalInp = getDigitalIn('all','filename',"digitalin.dat",'fs',session.extracellular.sr);
    end
end

% Epochs derived from digital inputs for multianimal recordings
if exist(fullfile(basepath,['digitalIn.events.mat']),'file')
    load(fullfile(basepath,['digitalIn.events.mat']))
    
    if exist('digitalIn','var')
        parsed_digitalIn = digitalIn;
        clear digitalIn
    end
    
    if acquisition_event_flag
        start_idx = 2;
        % first and last time stamp are always acquisition
        session.epochs{1}.name =  'acquisition';
        session.epochs{1}.startTime =  parsed_digitalIn.timestampsOn{1, 2}(1);
        session.epochs{1}.stopTime = parsed_digitalIn.timestampsOn{1, 2}(end);
        
    else
        start_idx = 1;
    end
    
    % loop through the other epochs
    ii = start_idx;
    for i = start_idx:2:size(parsed_digitalIn.timestampsOn{1, 2},1)-1 % by default 2nd column is events
        session.epochs{ii}.name =  char(i);
        session.epochs{ii}.startTime =  parsed_digitalIn.timestampsOn{1, 2}(i);
        session.epochs{ii}.stopTime =  parsed_digitalIn.timestampsOff{1, 2}(i+1);
        ii = ii+1;
    end
else
    disp('No digitalIn.events.mat found in basepath.')
end
save(fullfile(basepath,[basename, '.session.mat']),'session');

%  annotate session epochs
if check_epochs
    gui_session
end


% Auxilary input
if getAcceleration
    accel = computeIntanAccel('saveMat',true);
end

% remove noise from data for cleaner spike sorting
if removeNoise
    NoiseRemoval(basepath); % not very well tested yet
end

if getLFP
    % create downsampled lfp low-pass filtered lfp file
    LFPfromDat(basepath,'outFs',lfp_fs,'useGPU',true);
end

% Calcuate estimated emg
if getEMG
    chInfo = hackInfo('basepath',basepath);
    EMGFromLFP = getEMGFromLFP(basepath,'overwrite',false,'noPrompts',true,...
        'saveMat',true,'chInfo',chInfo,'specialChannels',specialChannels);
end

% Get brain states
% an automatic way of flaging bad channels is needed
if stateScore
    if exist('pulses','var')
        SleepScoreMaster(basepath,'noPrompts',true,'ignoretime',pulses.intsPeriods); % try to sleep score
        thetaEpochs(basepath);
    else
        SleepScoreMaster(basepath,'noPrompts',true); % takes lfp in base 0
        thetaEpochs(basepath);
    end
end

if kilosort
    % For Kilosort: create channelmap
    create_channelmap(basepath)
    
    % creating a folder on the ssd for chanmap,dat, and xml
    ssd_folder = fullfile(ssd_path, basename);
    mkdir(ssd_folder);
    
    % Copy chanmap,basename.dat, and xml
    disp('Copying basename.dat, basename.xml, and channelmap to ssd')
    
    disp('Saving dat file to ssd')
    command = ['robocopy "',basepath,'" ',ssd_folder,' ',basename,'.dat'];
    system(command);
    
    disp('Saving xml to ssd')
    command = ['robocopy "',basepath,'" ',ssd_folder,' ',basename,'.xml'];
    system(command);
    
    disp('Saving channel_map to ssd')
    command = ['robocopy "',basepath,'" ',ssd_folder,' chanMap.mat'];
    system(command);
    
    % Spike sort using kilosort 1 (data on ssd)
    run_ks1(basepath,ssd_folder)
end
% Get tracking positions
% check for DLC csv
dlc_files = dir([basepath,filesep,'*DLC*.csv']);

if ~isempty(dlc_files)
    general_behavior_file_SNlab('basepath',basepath)
    
    load(fullfile(basepath,[basename,'.animal.behavior.mat']))
    
    if ~isempty(behavior.position.x)
        start = [];
        stop = [];
        maze_size = [];
        for ep = 1:length(session.epochs)
            if contains(session.epochs{ep}.environment,{'open_field','linear_track'})
                start = [start,session.epochs{ep}.startTime];
                stop = [stop,session.epochs{ep}.stopTime];
                
                if ismember(session.epochs{ep}.environment,'open_field')
                    maze_size = [maze_size; 30];
                elseif ismember(session.epochs{ep}.environment,'linear_track')
                    maze_size = [maze_size; 120];
                end
            end
        end
        
        good_idx = manual_trackerjumps(behavior.timestamps,...
            behavior.position.x,...
            behavior.position.y,...
            start,...
            stop,...
            basepath,'darkmode',false);
        
        behavior.position.x(~good_idx) = NaN;
        behavior.position.y(~good_idx) = NaN;
        
        % rescale coordinates 
        scale_factor = (max(behavior.position.x) - min(behavior.position.x))/maze_size; %pixels/cm
        
        coord_names = fieldnames(behavior.position); 
       for i = find(contains(coord_names,{'x','y'}))'
           behavior.position.(coord_names{i}) = behavior.position.(coord_names{i})/scale_factor;
       end
       
        behavior.position.units = 'cm';
       
        save(fullfile(basepath,[basename,'.animal.behavior.mat']),'behavior')
    end
    
end



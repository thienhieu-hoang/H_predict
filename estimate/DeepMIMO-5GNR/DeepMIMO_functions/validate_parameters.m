% --------- DeepMIMO: A Generic Dataset for mmWave and massive MIMO ------%
% Authors: Umut Demirhan, Abdelrahman Taha, Ahmed Alkhateeb
% Date: March 17, 2022
% Goal: Encouraging research on ML/DL for MIMO applications and
% providing a benchmarking tool for the developed algorithms
% ---------------------------------------------------------------------- %

function [params, params_inner] = validate_parameters(params)

    [params] = compare_with_default_params(params);

    [params, params_inner] = additional_params(params);

    params_inner = validate_CDL5G_params(params, params_inner);
end

% Check the validity of the given parameters
% Add default parameters if they don't exist in the current file
% Does not compare the details of .CDL_5G structure
function [params] = compare_with_default_params(params)
    default_params = read_params('default_parameters.m');
    params = compare_structure(params, default_params);
    params.('CDL_5G') = compare_structure(params.('CDL_5G'), default_params.('CDL_5G'));
    
    function cur_struct = compare_structure(cur_struct, default_struct)
        ignored_params = {'dataset_folder', 'bsCustomAntenna', 'ueCustomAntenna'};
        default_fields = fieldnames(default_struct);
        fields = fieldnames(cur_struct);
        default_fields_exist = zeros(1, length(default_fields));
        for i = 1:length(fields)
            comp = strcmp(fields{i}, default_fields);
            if sum(comp) == 1
                default_fields_exist(comp) = 1;
            else
                if ~any(strcmp(fields{i}, ignored_params))
                    fprintf('\nThe parameter "%s" defined in the given parameters is not used by DeepMIMO', fields{i}) 
                end
            end
        end
        default_fields_exist = ~default_fields_exist;
        default_nonexistent_fields = find(default_fields_exist);
        for i = 1:length(default_nonexistent_fields)
            field = default_fields{default_nonexistent_fields(i)};
            value = getfield(default_struct, field);
            cur_struct = setfield(cur_struct, field, value);
            fprintf('\nAdding default parameter: %s - %s', field, num2str(value)) 
        end
    end
end


function [params, params_inner] = additional_params(params)

    % Add dataset path
    if ~isfield(params, 'dataset_folder')
        current_folder = mfilename('fullpath');
        deepmimo_folder = fileparts(fileparts(current_folder));
        params_inner.dataset_folder = fullfile(deepmimo_folder, '/Raytracing_scenarios/');

        % Create folders if not exists
        folder_one = fullfile(deepmimo_folder, '/Raytracing_scenarios/');
        folder_two = fullfile(deepmimo_folder, '/DeepMIMO_dataset/');
        if ~exist(folder_one, 'dir')
            mkdir(folder_one);
        end
        if ~exist(folder_two, 'dir')
            mkdir(folder_two)
        end
    else
        params_inner.dataset_folder = fullfile(params.dataset_folder);
    end
    
    scenario_folder = fullfile(params_inner.dataset_folder, params.scenario);
    assert(logical(exist(scenario_folder, 'dir')), ['There is no scenario named "' params.scenario '" in the folder "' scenario_folder '/"' '. Please make sure the scenario name is correct and scenario files are downloaded and placed correctly.']);

    % Determine if the scenario is dynamic
    params_inner.dynamic_scenario = 0;
    if ~isempty(strfind(params.scenario, 'dyn'))
        params_inner.dynamic_scenario = 1;
        list_of_folders = strsplit(sprintf('/scene_%i/--', params.scene_first-1:params.scene_last-1),'--');
        list_of_folders(end) = [];
        list_of_folders = fullfile(params_inner.dataset_folder, params.scenario, list_of_folders);
    else
        list_of_folders = {fullfile(params_inner.dataset_folder, params.scenario)};
    end
    params_inner.list_of_folders = list_of_folders;
    
    % Check data version and load parameters of the scenario
    params_inner.data_format_version = checkDataVersion(scenario_folder);
    version_postfix = strcat('v', num2str(params_inner.data_format_version));
    
    % Load Scenario Parameters (version specific)
    load_scenario_params_fun = strcat('load_scenario_params_', version_postfix);
    [params, params_inner] = feval(load_scenario_params_fun, params, params_inner);
    
    % Select raytracing function (version specific)
    params_inner.raytracing_fn = strcat('read_raytracing_', version_postfix);
    
    params.num_active_BS =  length(params.active_BS);

    validateUserParameters(params);
    [params.user_ids, params.num_user] = find_users(params);
end


function version = checkDataVersion(scenario_folder)
    new_params_file = fullfile(scenario_folder, 'params.mat');
    if exist(new_params_file, 'file') == 0
        version = 2;
    else
        version = 3;
    end
end

function [params, params_inner] = load_scenario_params_v3(params, params_inner)
  
    if params_inner.dynamic_scenario == 1 
        list_of_folders = strsplit(sprintf('scene_%i--', params.scene_first-1:params.scene_last-1),'--');
        list_of_folders(end) = [];
        list_of_folders = fullfile(params_inner.dataset_folder, params.scenario, list_of_folders);
    else
        list_of_folders = {fullfile(params_inner.dataset_folder, params.scenario)};
    end
    params_inner.list_of_folders = list_of_folders;
    
    % Read scenario parameters
    params_inner.scenario_files=params_inner.list_of_folders{1}; % The initial of all the scenario files
    params_file = fullfile(params_inner.dataset_folder, params.scenario, 'params.mat');
    
    load(params_file) % Scenario parameter file
    
    params.carrier_freq = carrier_freq; % in Hz
    params.transmit_power_raytracing = transmit_power; % in dB
    params.user_grids = user_grids;
    params.num_BS = num_BS;
    %params.BS_grids = BS_grids;
    %params.BS_ID_map = TX_ID_map; % New addition for the new data format
    
    params_inner = findUserFileSplit(params_inner);
    params_inner.doppler_available = doppler_available;
    params_inner.dual_polar_available = dual_polar_available;
    
end

function [params, params_inner] = load_scenario_params_v2(params, params_inner)
  
    if params_inner.dynamic_scenario == 1
        list_of_folders = strsplit(sprintf('/scene_%i/--', params.scene_first-1:params.scene_last-1),'--');
        list_of_folders(end) = [];
        list_of_folders = fullfile(params_inner.dataset_folder, params.scenario, list_of_folders);
    else
        list_of_folders = {fullfile(params_inner.dataset_folder, params.scenario)};
    end
    params_inner.list_of_folders = list_of_folders;
    
    % Read scenario parameters
    params_inner.scenario_files=fullfile(list_of_folders{1}, params.scenario); % The initial of all the scenario files
    load([params_inner.scenario_files, '.params.mat']) % Scenario parameter file
    params.carrier_freq = carrier_freq; % in Hz
    params.transmit_power_raytracing = transmit_power; % in dBm
    params.user_grids = user_grids;
    params.num_BS = num_BS;
    
    % BS-BS channel parameters
    load([params_inner.scenario_files, '.BSBS.params.mat']) % BS2BS parameter file
    params.BS_grids = BS_grids;
    
end

function [params_inner] = validate_CDL5G_params(params, params_inner)
    % Polarization
    assert(params.CDL_5G.polarization == 1 | params.CDL_5G.polarization == 0, 'Polarization value should be an indicator (0 or 1)')

    % UE Antenna
    if params.CDL_5G.customAntenna
        params_inner.ueAntenna = params.CDL_5G.ueCustomAntenna;
    else
        params_inner.ueAntenna = params.CDL_5G.ueAntSize;
    end

    % BS Antenna
    if params.CDL_5G.customAntenna % Custom Antenna
        if length(params.CDL_5G.bsCustomAntenna) ~= params.num_active_BS
            if length(params.CDL_5G.bsCustomAntenna) == 1
                antenna = params.CDL_5G.bsCustomAntenna;
                params_inner.bsAntenna = cell(1, params.num_active_BS);
                for ant_idx=1:params.num_active_BS
                    params_inner.bsAntenna{ant_idx} = antenna;
                end
            else
                error('The number of defined BS custom antenna should be either single or a cell array of N custom antennas, where N is the number of active BSs.')
            end
        else
            if ~iscell(params.CDL_5G.bsCustomAntenna)
                params_inner.bsAntenna = {params.CDL_5G.bsCustomAntenna};
            else
                params_inner.bsAntenna = params.CDL_5G.bsCustomAntenna;
            end
        end
    else % Size input
        % Check BS antenna size
        ant_size = size(params.CDL_5G.bsAntSize);
        assert(ant_size(2) == 2, 'The defined BS antenna panel size must be 2 dimensional (rows - columns)')
        if ant_size(1) ~= params.num_active_BS
            if ant_size(1) == 1
                params_inner.bsAntenna = repmat(params.CDL_5G.bsAntSize, params.num_active_BS, 1);
            else
                error('The defined BS antenna panel size must be either 1x2 or Nx2 dimensional, where N is the number of active BSs.')
            end
        else
            params_inner.bsAntenna = params.CDL_5G.bsAntSize;
        end
        
        if ~iscell(params_inner.bsAntenna)
            params_inner.bsAntenna = num2cell(params_inner.bsAntenna, 2);
        end
    end
    
    % Check BS Antenna Orientation
    ant_size = size(params.CDL_5G.bsArrayOrientation);
    assert(ant_size(2) == 2, 'The defined BS antenna orientation size must be 2 dimensional (azimuth - elevation)')
    if ant_size(1) ~= params.num_active_BS
        if ant_size(1) == 1
            params_inner.bsOrientation = repmat(params.CDL_5G.bsArrayOrientation, params.num_active_BS, 1);
        else
            error('The defined BS antenna orientation size must be either 1x2 or Nx2 dimensional, where N is the number of active BSs.')
        end
    else
        params_inner.bsOrientation = params.CDL_5G.bsArrayOrientation;
    end
    if ~iscell(params_inner.bsOrientation)
        params_inner.bsOrientation = num2cell(params_inner.bsOrientation, 2);
    end
    
    % Velocity
    if length(params.CDL_5G.Velocity) == 2
        params_inner.velocity = unifrnd(params.CDL_5G.Velocity(1), params.CDL_5G.Velocity(2), params.num_user, 1);
    elseif length(params.CDL_5G.Velocity) == 1
        params_inner.velocity = repmat(params.CDL_5G.Velocity, params.num_user, 1);
    else
        error('The defined velocity must be either 1 or 2 dimensional for fixed or random values.')
    end
    
    % Travel Direction
    size_travel_dir = size(params.CDL_5G.UTDirectionOfTravel);
    params_inner.travel_dir = zeros(params.num_user, 2);
    if sum(size_travel_dir == 2) == 2
        for i = 1:2
            params_inner.travel_dir(:, i) = unifrnd(params.CDL_5G.UTDirectionOfTravel(i, 1), params.CDL_5G.UTDirectionOfTravel(i, 2), params.num_user, 1);
        end
    elseif sum(size_travel_dir == [1, 2]) == 2
        for i = 1:2
            params_inner.travel_dir(:, i) = params.CDL_5G.UTDirectionOfTravel(i);
        end
    else
        error('The defined travel direction must be either 1x2 or 2x2 dimensional for fixed or random values.')
    end

    % UE Antenna Direction
    size_ue_orientation = size(params.CDL_5G.ueArrayOrientation);
    params_inner.ueOrientation = zeros(params.num_user, 2);
    if sum(size_ue_orientation == 2) == 2
        for i = 1:2
            params_inner.ueOrientation(:, i) = unifrnd(params.CDL_5G.ueArrayOrientation(i, 1), params.CDL_5G.ueArrayOrientation(i, 2), params.num_user, 1);
        end
    elseif sum(size_ue_orientation == [1, 2]) == 2
        for i = 1:2
            params_inner.ueOrientation(:, i) = params.CDL_5G.ueArrayOrientation(i);
        end
    else
        error('The defined user array orientation must be either 1x2 or 2x2 dimensional for fixed or random values.')
    end
end

% Find how the user files are split to multiple files with subset of users
% E.g., 0-10k 10k-20k ... etc
function params_inner = findUserFileSplit(params_inner)
    % Get a list of UE split
    fileList = dir(fullfile(params_inner.scenario_files, '*.mat'));
    filePattern = 'BS1_UE_(\d+)-(\d+)\.mat';

    number1 = [];
    number2 = [];

    % Loop through each file and extract the numbers
    for i = 1:numel(fileList)
        filename = fileList(i).name;

        % Check if the file name matches the pattern
        match = regexp(filename, filePattern, 'tokens');

        if ~isempty(match)
            % Extract the numbers from the file name
            number1 = [number1 str2double(match{1}{1})];
            number2 = [number2 str2double(match{1}{2})];
        end
    end
    params_inner.UE_file_split = [number1; number2];
end

function [] = validateUserParameters(params)
    assert(params.row_subsampling<=1 & params.row_subsampling>0, 'Row subsampling parameters must be selected in (0, 1]')
    assert(params.user_subsampling<=1 & params.user_subsampling>0, 'User subsampling parameters must be selected in (0, 1]')

    assert(params.active_user_last <= params.user_grids(end, 2) & params.active_user_last >= 1, sprintf('There are total %i user rows in the scenario, please select the active user first and last in [1, %i]', params.user_grids(end, 2), params.user_grids(end, 2)));
    assert(params.active_user_first <= params.active_user_last, 'active_user_last parameter must be greater than or equal to active_user_first');
end
% Parametric modifications of RTSA implant geometry configurations (humeral cup and
% glenosphere) and shoulder anatomy (humerus and scapula) to approximate
% "Virtual Surgery" in RTSA. Main output of this program is to adjust the
% relative position of the humerus with respect to the scapula after the
% RTSA implant components with selected configurations have been positioned
% on the respective anatomies. The configurations include congruent cup and
% hemisphere radii (R_cup = R_hemisphere), position (antero/posterior,
% supero/inferial and base offset) and orientation (antero/postero,
% supero/infero version) of the components. When geometric modification
% have been completed on each anatomy and the implant component positions
% are defined the parametic approximation of the components are exported as
% .stl and then the two anatomies and implant componets are registered in
% the global coordinate system. The newly created shoulder joint CoR in the
% scapula (parent body) and humerus (child body) are exported and redefined
% in OpenSim.
%
% Critical functions:
% axang2rotm, vrrotvec, rotate, fmincon
%
% %%%%%%%%%%%%%%%%%%%%%%%%%%%% TO ADD  %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% 1) Reaming depth on glenoid (translate glenoid plane along -Z norm of
%       glenoid plane
% 2) Interactivly chose surgical configuration parameters and updating
%       visualiser and data to pass onto next step?
%       (https://www.mathworks.com/help/control/ug/build-app-with-interactive-plot-updates.html)
%
%
% Pavlos Silvestros, PhD - University of Victoria, CAN, June 2022

close all;
clear;
clc;

% Time the run
time_i = datetime;
%% Set-up
set(0,'DefaultFigureVisible','on');
%%%%%%%%%%%%%%%%% Create parameter combinations for loops %%%%%%%%%%%%%%%%%
design_param.diameter                   = {0.039};

design_param.glenoid_base_off           = {0}; % Equivelant to baseplate offset
design_param.glenoid_prox_dist          = {0};
design_param.glenoid_ant_post           = {0};

design_param.glenoid_sup_inf_incl       = {0};
design_param.gelnoid_ant_retro_version  = {0};

design_param.humerus_base_off           = {0.001};
design_param.humerus_prox_dist          = {0};
design_param.humerus_ant_post           = {0};

design_param.humerus_sup_inf_incl       = {12.5};
design_param.humerus_ant_retro_version  = {0};

scapula_morphologies = {
%     'm3_-3_m2_-3',...
    'm3_-3_m2_3',...
%     'm3_-3_m2_-1',...
%     'm3_-3_m2_1',...
%     'm3_-3_m4_-3',...
%     'm3_-3_m4_3',...
%     'm3_-3_m4_-1',...
%     'm3_-3_m4_1',...
%     'm3_-3_m5_-3',...
%     'm3_-3_m5_3',...
%     'm3_-3_m5_-1',...
%     'm3_-3_m5_1',...
%     'm3_-3_m6_-3',...
%     'm3_-3_m6_-1',...
%     'm3_-3_m6_1',...
%     'm3_-3_m6_3',...
%     'm3_-3_m1_0',...
%     'm3_-3_m7_-3',...
%     'm3_-3_m7_-1',...
%     'm3_-3_m7_1',...
%     'm3_-3_m7_3',...
%     'm3_-3_m9_-1',...
%     'm3_-3_m9_1',...
%     'm3_-3_m9_-3',...
%     'm3_-3_m9_3',...
    };

% Re-shufle morphology order for evaluation purposes
% scapula_morphologies = scapula_morphologies(randperm(numel(scapula_morphologies)));

motion_tasks                            = {
    'UpwardReach',...
    %                                            'LateralReach',...
    %                                            'HairTouch'
    };

% Create permutation matrix
param_matrix= allcomb( ...
    design_param.diameter,...
    design_param.glenoid_base_off, ...
    design_param.glenoid_prox_dist, ...
    design_param.glenoid_ant_post, ...
    design_param.glenoid_sup_inf_incl, ...
    design_param.gelnoid_ant_retro_version,...
    design_param.humerus_base_off,...
    design_param.humerus_prox_dist,...
    design_param.humerus_ant_post,...
    design_param.humerus_sup_inf_incl,...
    design_param.humerus_ant_retro_version,...
    scapula_morphologies,...
    motion_tasks...
    );

% Split matrix
param_diameter              = param_matrix(:,1);
param_glenoid_base_off      = param_matrix(:,2);
param_glenoid_prox_dist     = param_matrix(:,3);
param_glenoid_ant_post      = param_matrix(:,4);

param_glenoid_inclination   = param_matrix(:,5);
param_glenoid_version       = param_matrix(:,6);

param_humerus_base_off      = param_matrix(:,7);
param_humerus_prox_dist     = param_matrix(:,8);
param_humerus_ant_post      = param_matrix(:,9);

param_humerus_inclination   = param_matrix(:,10);
param_humerus_version       = param_matrix(:,11);

param_morphologies          = param_matrix(:,12);
param_tasks                 = param_matrix(:,end);

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% Flags %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% If use parallel with 2 workers (18 threads/worker) to batch job
flag_useParallel        = false;

% If should plot intermediate plots for checking
flag_checkPlots         = false;

% If replacing Muscles with Actuators
flag_useTorque          = false;

% If removing Rotator Cuff muscles
flag_keepRC             = false;

% Replace muscle models Millard2012Equilibrium with DeGrootFregly
flag_ReplaceMuscles     = true;

% Run Moco after model is defined?
flag_runSim             = false;

% Correct morphology's Version / Inclination angles and 12 mm rule
flag_correctVersion     = false;
flag_correctInclination = true;
flag_correctProxDist    = true;
flag_correctLateral     = true;

% Optimise DELT1, DELT2 and DELT3 via points
flag_viaPointOpt        = false;

flag_DELT1              = true; % Optimises position of via-point
flag_DELT2              = true; % Optimises or Deletes via-point
flag_DELT3              = true; % Optimises or Deletes via-point

%% Pass setup parameters and prepare models/simulations
if flag_useParallel == true

    %%%%%%%%%%%%%%%%%%%%%%%%% Parallel Computing %%%%%%%%%%%%%%%%%%%%%%%%%%

    % Number of Workers
    n_workers     = 2;
    n_threads     = 36/n_workers;

    % Specify maximum number of computational threads (?)
    % maxNumCompThreads(n_threads);

    % Create parallel pool
    pool = parpool('2Workers');

    parfor i_param = 1:size(param_matrix,1)
        %% Define Parameters for hemisphere/cup gemetry and offsets

        %%%%%%%%%%%%%%%%%%%%%%% Hemisphere radius %%%%%%%%%%%%%%%%%%%%%%%%%
        diameter = param_diameter{i_param};

        R = diameter/2;

        %%%%%%%%%%%%%%%%%%%%%%% Glenosphere offsets %%%%%%%%%%%%%%%%%%%%%%%

        hemi_gle_offsets = struct();

        % Rotation offsets in degrees

        % Anteroversion: +ive; Retroversion: -ive
        hemi_gle_offsets.y_ant_retro_version    = param_glenoid_version{i_param};
        % Inferior inclination: - ive; Superior inclination: +ive
        hemi_gle_offsets.x_sup_inf_incl         = param_glenoid_inclination{i_param};

        % Translation offsets in meters (m)
        hemi_gle_offsets.x_ant_post   = param_glenoid_ant_post{i_param};          % X-normal
        hemi_gle_offsets.y_prox_dist  = param_glenoid_prox_dist{i_param};     % Y-normal
        hemi_gle_offsets.z_base_off   = param_glenoid_base_off{i_param};      % Z-normal

        %%%%%%%%%%%%%%%%%%%%%%% Humeral cup offsets %%%%%%%%%%%%%%%%%%%%%%%

        hemi_cup_offsets = struct();

        % Rotation offsets in degrees

        % Anteroversion: +ive; Retroversion: -ive
        hemi_cup_offsets.z_ant_retro_version   = param_humerus_version{i_param};
        % Inferior inclination: - ive; Superior inclination: +ive
        hemi_cup_offsets.x_sup_inf_incl        = param_humerus_inclination{i_param};

        % Translation offsets in meters (m)
        hemi_cup_offsets.x_ant_post   = param_humerus_ant_post{i_param};      % X-normal
        hemi_cup_offsets.y_base_off   = param_humerus_base_off{i_param};  % Y-normal
        hemi_cup_offsets.z_prox_dist  = param_humerus_prox_dist{i_param};      % Z-normal

        %%%%%%%%%%%%%%%%%%%%%%%% Model morphology %%%%%%%%%%%%%%%%%%%%%%%%%
        model_SSM = param_morphologies{i_param};

        %%%%%%%%%%%%%%%%%%%%%%%% Simulation task %%%%%%%%%%%%%%%%%%%%%%%%%%
        task_name = param_tasks{i_param}

        % Create a random 11-char hash to reference model file X00yyy111zz (~30e12)
        % Add random pause between 0.25-0.50 seconds to print files in parfor
        pause(0.250 + rand*0.250)
        rng('shuffle');
        rhash = [char(randi([65 90],1,1))...
            char(randi([48 57],1,2))...
            char(randi([97 122],1,3))...
            char(randi([48 57],1,3))...
            char(randi([97 122],1,2))];

        %%
        %%%%%%%%%%%%%%%%%%%%%%%%%% Call functions %%%%%%%%%%%%%%%%%%%%%%%%%
        % Create internal functions here (one for humerus and one for scapula) that
        % plot and do all the positioning then only return necessary values and
        % data.

        % Define parametric implant on .stl anatomy & extract parameters in global
        scapula = glenoidGeom(R, hemi_gle_offsets, model_SSM, rhash, flag_correctVersion, flag_correctInclination, flag_correctProxDist, flag_correctLateral);

        % Define parametric implant on .stl anatomy & extract parameters in global
        humerus = humerusGeom(R, hemi_cup_offsets, rhash);

        % Read in defined implant parameters and .stl and calculate GHJ centre
        [GHJ_in_parent, GHJ_in_child] = jointCalculationGH(scapula,humerus);

        % Define OpenSim model with new GHJ parameters from 'Virtual Surgery'
        model_file = adjustOpenSimModelGHJ(GHJ_in_parent,...
            scapula.glenoid_plane_normals.theta,...
            GHJ_in_child,...
            scapula.hemi_gle_offsets,...
            humerus.hemi_cup_offsets,...
            R,...
            rhash,...
            model_SSM,...
            task_name,...
            flag_useTorque,...
            flag_keepRC,...
            flag_ReplaceMuscles);

        close all

        % Run OpenSim moco for predictive simulation
        if flag_runSim == true
            runRTSAsims(model_file, rhash, flag_keepRC, task_name)
        end

    end

elseif flag_useParallel == false
    for i_param = 1:size(param_matrix,1)
        %% Define Parameters for hemisphere/cup gemetry and offsets

        %%%%%%%%%%%%%%%%%%%%%%% Hemisphere radius %%%%%%%%%%%%%%%%%%%%%%%%%
        diameter = param_diameter{i_param};

        R = diameter/2;

        %%%%%%%%%%%%%%%%%%%%%%% Glenosphere offsets %%%%%%%%%%%%%%%%%%%%%%%

        hemi_gle_offsets = struct();

        % Rotation offsets in degrees

        % Anteroversion: +ive; Retroversion: -ive
        hemi_gle_offsets.y_ant_retro_version    = param_glenoid_version{i_param};
        % Inferior inclination: - ive; Superior inclination: +ive
        hemi_gle_offsets.x_sup_inf_incl         = param_glenoid_inclination{i_param};

        % Translation offsets in meters (m)
        hemi_gle_offsets.x_ant_post   = param_glenoid_ant_post{i_param};          % X-normal
        hemi_gle_offsets.y_prox_dist  = param_glenoid_prox_dist{i_param};     % Y-normal
        hemi_gle_offsets.z_base_off   = param_glenoid_base_off{i_param};      % Z-normal

        %%%%%%%%%%%%%%%%%%%%%%% Humeral cup offsets %%%%%%%%%%%%%%%%%%%%%%%

        hemi_cup_offsets = struct();

        % Rotation offsets in degrees

        % Anteroversion: +ive; Retroversion: -ive
        hemi_cup_offsets.z_ant_retro_version   = param_humerus_version{i_param};
        % Inferior inclination: - ive; Superior inclination: +ive
        hemi_cup_offsets.x_sup_inf_incl        = param_humerus_inclination{i_param};

        % Translation offsets in meters (m)
        hemi_cup_offsets.x_ant_post   = param_humerus_ant_post{i_param};      % X-normal
        hemi_cup_offsets.y_base_off   = param_humerus_base_off{i_param};  % Y-normal
        hemi_cup_offsets.z_prox_dist  = param_humerus_prox_dist{i_param};      % Z-normal

        %%%%%%%%%%%%%%%%%%%%%%%% Model morphology %%%%%%%%%%%%%%%%%%%%%%%%%
        model_SSM = param_morphologies{i_param};

        %%%%%%%%%%%%%%%%%%%%%%%% Simulation task %%%%%%%%%%%%%%%%%%%%%%%%%%
        task_name = param_tasks{i_param};

        % Create a random 11-char hash to reference model file X00yyy111zz (~30e12)
        % Add random pause between 0.25-0.50 seconds to print files in parfor
        pause(0.250 + rand*0.250)
        rng('shuffle');
        rhash = [char(randi([65 90],1,1))...
            char(randi([48 57],1,2))...
            char(randi([97 122],1,3))...
            char(randi([48 57],1,3))...
            char(randi([97 122],1,2))];

        %%
        %%%%%%%%%%%%%%%%%%%%%%%%%% Call functions %%%%%%%%%%%%%%%%%%%%%%%%%
        % Create internal functions here (one for humerus and one for scapula) that
        % plot and do all the positioning then only return necessary values and
        % data.

        % Define parametric implant on .stl anatomy & extract parameters in global
        scapula = glenoidGeom(R, hemi_gle_offsets, model_SSM, rhash, flag_correctVersion, flag_correctInclination, flag_correctProxDist, flag_correctLateral);

        % Define parametric implant on .stl anatomy & extract parameters in global
        humerus = humerusGeom(R, hemi_cup_offsets, rhash);

        % Read in defined implant parameters and .stl and calculate GHJ centre
        [GHJ_in_parent, GHJ_in_child] = jointCalculationGH(scapula,humerus);

        close 10 20 1

        % Define OpenSim model with new GHJ parameters from 'Virtual Surgery'
        model_file = adjustOpenSimModelGHJ(GHJ_in_parent,...
            scapula.glenoid_plane_normals.theta,...
            GHJ_in_child,...
            scapula.hemi_gle_offsets,...
            humerus.hemi_cup_offsets,...
            R,...
            rhash,...
            model_SSM,...
            task_name,...
            flag_useTorque,...
            flag_keepRC,...
            flag_ReplaceMuscles);

        % Save out vars for the runRTSAtrack.m or runRTSAsims.m function on Cluster
        save(['..\..\OpenSim\In\Models\RTSA_Adjusted\' rhash],...
            'flag_keepRC', ...
            'task_name', ...
            'GHJ_in_parent', ...
            'GHJ_in_child', ...
            'scapula', ...
            'humerus', ...
            'R', ...
            'rhash', ...
            'model_SSM');

        if flag_viaPointOpt  == true
            optimDeltViaPoint(model_file, flag_DELT1, flag_DELT2, flag_DELT3)
        end

        close all

        % Run OpenSim moco for predictive simulation
        if flag_runSim == true
            runRTSAtrack(model_file,...
                flag_keepRC,...
                task_name,...
                GHJ_in_parent,...
                GHJ_in_child,...
                scapula.hemi_gle_offsets,...
                humerus.hemi_cup_offsets,...
                R,...
                rhash,...
                model_SSM);
        end

    end
end

% Show entire time of simulation batch
time_f = datetime;
run_time = time_f - time_i;

disp('#######################################################');
disp('Overall simulation batch took....');
disp(' ');
disp(run_time);
disp('#######################################################');

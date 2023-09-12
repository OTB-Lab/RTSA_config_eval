function scapula = glenoidGeom(R, hemi_gle_offsets, model_SSM, rhash, flag_correctVersion, flag_correctInclination, flag_correctProxDist, flag_correctLateral, flag_AthwalOr12mm)

%% Flags 
% What part of the glenoid will be used to calcuate glenoid plane? (global
% (i.e. full glenoid) [= true] or lower [= false] for RSA) -- lower is the emerging standard as
% laid out by this paper: https://www.jshoulderelbow.org/article/S1058-2746(18)30937-6/fulltext
flag_globalGlenoid = true;

% Use global glenoid norm calculation for lower RSA positioning? (Clinical
% Study Jaylan will focus on) INCLUDE flag_AthwalOr12mm = true
flag_global4LowerGlenoid = false;
    %to be clear, for Jaylan's study, we are interested in what happens if
    %person calculated glenoid plane using full glenoid (e.g. global) when
    %they plan to place the implant in the lower half vs the new way of using 
    % only the lower half to calculate the glenoid plane and then placing 
    % it in the lower half. We will test two conditions for each configuration:
    % 1. The 'incorrect' calculation is represented by this combination of flags
    %"flag_globalGlenoid == false && flag_global4LowerGlenoid == true". 
    % 2. The correct calculation for the new "RSA angle" method for when you want
    %to place the baseplate in the lower half is achieved using the
    %conditions "flag_globalGlenoid == false && flag_global4LowerGlenoid ==
    %false".

% Inferior overhang (used in Athwal for calculation otherwise just
% visualisation of a point at this distance)
overhang = 0.007;
% Lateral offset from inferior rim (used in Athwal for calculation otherwise just
% visualisation of a point at this distance)
offset = 0.002;

%% Set up
% Load in and configure points of Scapula .stl
% NOTE: not the most efficient way of handling the .stl
[x, y, z] = stlreadXYZ(['..\SSM\Scapulas\stl_aligned\' model_SSM '.stl']);

figure(10);

% Plot global coordinate system
x_hat=[0.1 0 0];
y_hat=[0 0.1 0];
z_hat=[0 0 0.1];

line([x_hat(1) 0],[x_hat(2) 0],[x_hat(3) 0], 'LineWidth',4,'Color','r'); % X - Red
line([y_hat(1) 0],[y_hat(2) 0],[y_hat(3) 0], 'LineWidth',4,'Color','y'); % Y - Yellow
line([z_hat(1) 0],[z_hat(2) 0],[z_hat(3) 0], 'LineWidth',4,'Color','g'); % Z - Green

% Plot .stl
patch(x,y,z,'b',...
    'FaceColor', [0.8 0.8 0.8],...
    'FaceAlpha', 0.75,...
    'EdgeColor', [0.65 0.65 0.65],...
    'EdgeAlpha', 0.5);

xlabel('X-axis');
ylabel('Y-axis');
zlabel('Z-axis');

axis equal

view(3)
hold on;


%% Fit plane to glenoid points 
% Note: the calculations in the first and second if statement section are
% the same but using different amounts of the glenoid surface points while
% the third part of the if statement does both sets of calculations done in
% parts 1 and 2 and this case is used for Jaylan's study as described in
% comments above.
if flag_globalGlenoid == true && flag_global4LowerGlenoid == false %this option does what we did in our first paper...calculate the glenoid plane from all the global glenoid (all of it) and position the construct based of those measurements

    scapula_stl = stlread(['..\SSM\Scapulas\stl_aligned\' model_SSM '.stl']);
    load('glenoid_idx_global.mat') %Specify indices of glenoid pts in scapula SSM

    glenoid_stl.Points = scapula_stl.Points(glenoid_idx,:);

    % Fit plane to glenoid points. This is not the "true" glenoid plane as
    % that is calculated from the LS sphere later

    % Linear Regression method to fit plane
    x_gl = glenoid_stl.Points(:,1);
    y_gl = glenoid_stl.Points(:,2);
    z_gl = glenoid_stl.Points(:,3);

    DM = [x_gl, y_gl, ones(size(z_gl))];
    B = DM\z_gl;

    % Create meshgrid of plane from Linear Regresion
    [X,Y] = meshgrid(linspace(min(x_gl),max(x_gl),50), linspace(min(y_gl),max(y_gl),50));
    Z = B(1)*X + B(2)*Y + B(3)*ones(size(X));

    % Create point cloud Linear Regression plane (consistensy with following code)
    glenoid_plane_pointCloud = pointCloud([X(:), Y(:), Z(:)]);
    % Fit plane to the Linear Regresion plane points
    [glenoid_plane,~,~, ~] = pcfitplane(glenoid_plane_pointCloud, 0.0001, 'MaxNumTrials', 1e6);

    glenoid_barycentre = mean(glenoid_stl.Points);
    % Initial normal to correct for position of LS sphere
    glenoid_normal = glenoid_plane.Normal;

    [glenoid_normal, stl_scap] = checkGlenoidNorm(x, y, z, glenoid_normal, glenoid_barycentre);

    glenSphere_lsq.Radius = 0.030;

    % Initial guess - projection from center to 30 mm out
    x0 = glenoid_barycentre + glenoid_normal*0.030;
    x0(4) = glenSphere_lsq.Radius;

    [x_opt] = glenoidSphereFitLS(glenoid_stl, x0, glenoid_normal, glenoid_barycentre);
    glenSphere_lsq.Center = x_opt(1:3);
    glenSphere_lsq.Radius = x_opt(4);

    % Normalised radial line of LS sphere
    glenoid_normal = (glenSphere_lsq.Center - glenoid_barycentre)/norm(glenSphere_lsq.Center - glenoid_barycentre);
    % Redefine glenoid plane with LS normal at barycentre
    plane_delta = - sum(glenoid_normal.*glenoid_barycentre);
    glenoid_plane = planeModel([glenoid_normal plane_delta]);

    glenoid_plane_normals.z_p = glenoid_barycentre + R*glenoid_normal;
    scatter3(glenoid_plane_normals.z_p(1), glenoid_plane_normals.z_p(2), glenoid_plane_normals.z_p(3), 'filled', 'g', 'MarkerEdgeColor', 'black')

    % Generate sphere mesh
    [xs,ys,zs] = sphere(101);
    xs = xs*glenSphere_lsq.Radius(1);
    ys = ys*glenSphere_lsq.Radius(1);
    zs = zs*glenSphere_lsq.Radius(1);

    % Generate plane mesh
    [gle_plane_mesh_data.x_plane, gle_plane_mesh_data.y_plane] = meshgrid(-0.1:0.01:0.1);
    gle_plane_mesh_data.z_plane = -1*(glenoid_plane.Parameters(1)*gle_plane_mesh_data.x_plane ...
        + glenoid_plane.Parameters(2)*gle_plane_mesh_data.y_plane ...
        + glenoid_plane.Parameters(4))/glenoid_plane.Parameters(3);
    
    hold on;
    
    surf(gle_plane_mesh_data.x_plane, gle_plane_mesh_data.y_plane, gle_plane_mesh_data.z_plane,...
        'FaceColor','b',...
        'FaceAlpha', 0.25,...
        'EdgeAlpha', 0)

    surf(xs+glenSphere_lsq.Center(1), ys+glenSphere_lsq.Center(2), zs+glenSphere_lsq.Center(3), 'EdgeColor','none', 'FaceColor','b', 'FaceAlpha', 0.1)
    scatter3(scapula_stl.Points(glenoid_idx,1), scapula_stl.Points(glenoid_idx,2), scapula_stl.Points(glenoid_idx,3),'b')
    scatter3(glenSphere_lsq.Center(1), glenSphere_lsq.Center(2), glenSphere_lsq.Center(3), 'filled', 'b', 'MarkerEdgeColor', 'black')
    scatter3(glenoid_barycentre(1), glenoid_barycentre(2), glenoid_barycentre(3), 'filled', 'cyan')
    line([glenoid_barycentre(1) glenSphere_lsq.Center(1)], [glenoid_barycentre(2) glenSphere_lsq.Center(2)], [glenoid_barycentre(3) glenSphere_lsq.Center(3)],'Color', 'g', 'LineWidth', 4)
  
elseif flag_globalGlenoid == false && flag_global4LowerGlenoid == false  %this option corresponds to the new RSA angle method of calculate the glenoid plane from the lower glenoid and position the construct based of those measurements

    scapula_stl = stlread(['..\SSM\Scapulas\stl_aligned\' model_SSM '.stl']);
    load('glenoid_idx_lower.mat')


    glenoid_stl.Points = scapula_stl.Points(glenoid_lower_idx,:);

    % Fit plane to glenoid points. This is not the "true" glenoid plane as
    % that is calculated from the LS sphere later

    % Linear Regression method to fit plane
    x_gl = glenoid_stl.Points(:,1);
    y_gl = glenoid_stl.Points(:,2);
    z_gl = glenoid_stl.Points(:,3);

    DM = [x_gl, y_gl, ones(size(z_gl))];
    B = DM\z_gl;

    % Create meshgrid of plane from Linear Regresion
    [X,Y] = meshgrid(linspace(min(x_gl),max(x_gl),50), linspace(min(y_gl),max(y_gl),50));
    Z = B(1)*X + B(2)*Y + B(3)*ones(size(X));

    % Create point cloud Linear Regression plane (consistensy with following code)
    glenoid_plane_pointCloud = pointCloud([X(:), Y(:), Z(:)]);
    % Fit plane to the Linear Regresion plane points
    [glenoid_plane,~,~, ~] = pcfitplane(glenoid_plane_pointCloud, 0.0001, 'MaxNumTrials', 1e6);

    glenoid_barycentre = mean(glenoid_stl.Points);
    % Initial normal to correct for position of LS sphere
    glenoid_normal = glenoid_plane.Normal;

    [glenoid_normal, stl_scap] = checkGlenoidNorm(x, y, z, glenoid_normal, glenoid_barycentre);

    glenSphere_lsq.Radius = 0.030;

    % Initial guess - progection from center to 30 mm out
    x0 = glenoid_barycentre + glenoid_normal*0.030;
    x0(4) = glenSphere_lsq.Radius;

    [x_opt] = glenoidSphereFitLS(glenoid_stl, x0, glenoid_normal, glenoid_barycentre);
    glenSphere_lsq.Center = x_opt(1:3);
    glenSphere_lsq.Radius = x_opt(4);

    % Normalised radial line of LS sphere
    glenoid_normal = (glenSphere_lsq.Center - glenoid_barycentre)/norm(glenSphere_lsq.Center - glenoid_barycentre);
    % Redefine glenoid plane with LS normal at barycentre
    plane_delta = - sum(glenoid_normal.*glenoid_barycentre);
    glenoid_plane = planeModel([glenoid_normal plane_delta]);

    glenoid_plane_normals.z_p = glenoid_barycentre + R*glenoid_normal;
    scatter3(glenoid_plane_normals.z_p(1), glenoid_plane_normals.z_p(2), glenoid_plane_normals.z_p(3), 'filled', 'g', 'MarkerEdgeColor', 'black')

    % Generate sphere mesh
    [xs,ys,zs] = sphere(101);
    xs = xs*glenSphere_lsq.Radius(1);
    ys = ys*glenSphere_lsq.Radius(1);
    zs = zs*glenSphere_lsq.Radius(1);

    % Generate plane mesh using Ax + By + Gz + D = 0
    [gle_plane_mesh_data.x_plane, gle_plane_mesh_data.y_plane] = meshgrid(-0.1:0.01:0.1);
    gle_plane_mesh_data.z_plane = -1*(glenoid_plane.Parameters(1)*gle_plane_mesh_data.x_plane ...
        + glenoid_plane.Parameters(2)*gle_plane_mesh_data.y_plane ...
        + glenoid_plane.Parameters(4))/glenoid_plane.Parameters(3);
    
    hold on;

    surf(gle_plane_mesh_data.x_plane, gle_plane_mesh_data.y_plane, gle_plane_mesh_data.z_plane,...
        'FaceColor','b',...
        'FaceAlpha', 0.25,...
        'EdgeAlpha', 0)
    surf(xs+glenSphere_lsq.Center(1), ys+glenSphere_lsq.Center(2), zs+glenSphere_lsq.Center(3), 'EdgeColor','none', 'FaceColor','r', 'FaceAlpha', 0.1)
    scatter3(scapula_stl.Points(glenoid_lower_idx,1), scapula_stl.Points(glenoid_lower_idx,2), scapula_stl.Points(glenoid_lower_idx,3),'r')
    scatter3(glenSphere_lsq.Center(1), glenSphere_lsq.Center(2), glenSphere_lsq.Center(3), 'filled', 'r', 'MarkerEdgeColor','black')
    scatter3(glenoid_barycentre(1), glenoid_barycentre(2), glenoid_barycentre(3), 'filled', 'cyan')
    line([glenoid_barycentre(1) glenSphere_lsq.Center(1)], [glenoid_barycentre(2) glenSphere_lsq.Center(2)], [glenoid_barycentre(3) glenSphere_lsq.Center(3)],'Color', 'g', 'LineWidth', 4)
   

elseif flag_globalGlenoid == false && flag_global4LowerGlenoid == true  %this option is for testing the mistake of calculate the glenoid plane from all the global glenoid (all of it) and the resulting measurements (ie inclination and version) but position the construct on the lower glenoid based on the global measurements
    
    %% Calculate glenoid normal from global glenoid surface 
    % These calculations will be used later to pass to the correction of
    % the LOWER glenoid following RSA placement (lower) of glenosphere
    scapula_stl = stlread(['..\SSM\Scapulas\stl_aligned\' model_SSM '.stl']);
    load('glenoid_idx_global.mat')

    glenoid_stl.Points = scapula_stl.Points(glenoid_idx,:);

    % Fit plane to glenoid points. This is not the "true" glenoid plane as
    % that is calculated from the LS sphere later

    % Linear Regression method to fit plane
    x_gl = glenoid_stl.Points(:,1);
    y_gl = glenoid_stl.Points(:,2);
    z_gl = glenoid_stl.Points(:,3);

    DM = [x_gl, y_gl, ones(size(z_gl))];
    B = DM\z_gl;

    % Create meshgrid of plane from Linear Regresion
    [X,Y] = meshgrid(linspace(min(x_gl),max(x_gl),50), linspace(min(y_gl),max(y_gl),50));
    Z = B(1)*X + B(2)*Y + B(3)*ones(size(X));

    % Create point cloud Linear Regression plane (consistensy with following code)
    glenoid_plane_pointCloud = pointCloud([X(:), Y(:), Z(:)]);
    % Fit plane to the Linear Regresion plane points
    [glenoid_plane,~,~, ~] = pcfitplane(glenoid_plane_pointCloud, 0.0001, 'MaxNumTrials', 1e6);

    %%%

    glenoid_barycentre_global = mean(glenoid_stl.Points);
    % Initial normal to correct for position of LS sphere
    glenoid_normal = glenoid_plane.Normal;

    [glenoid_normal, stl_scap] = checkGlenoidNorm(x, y, z, glenoid_normal, glenoid_barycentre_global);

    glenSphere_lsq.Radius = 0.030;

    % Initial guess - progection from center to 30 mm out
    x0 = glenoid_barycentre_global + glenoid_normal*0.030;
    x0(4) = glenSphere_lsq.Radius;

    [x_opt] = glenoidSphereFitLS(glenoid_stl, x0, glenoid_normal, glenoid_barycentre_global);
    glenSphere_lsq.Center = x_opt(1:3);
    glenSphere_lsq.Radius = x_opt(4);

    % Normalised radial line of LS sphere
    glenoid_normal_global = (glenSphere_lsq.Center - glenoid_barycentre_global)/norm(glenSphere_lsq.Center - glenoid_barycentre_global);
    % Redefine glenoid plane with LS normal at barycentre
    plane_delta_global_glenoid = - sum(glenoid_normal_global.*glenoid_barycentre_global);
    glenoid_plane_global = planeModel([glenoid_normal_global plane_delta_global_glenoid]);

    % Generate plane mesh using Ax + By + Gz + D = 0 (for use when cashing
    % calculation of angles using global glenoid)
    [gle_plane_global_mesh_data.x_plane, gle_plane_global_mesh_data.y_plane] = meshgrid(-0.1:0.01:0.1);
    gle_plane_global_mesh_data.z_plane = -1*(glenoid_plane_global.Parameters(1)*gle_plane_global_mesh_data.x_plane ...
        + glenoid_plane_global.Parameters(2)*gle_plane_global_mesh_data.y_plane ...
        + glenoid_plane_global.Parameters(4))/glenoid_plane_global.Parameters(3);

    %% Continue with calculation of lower glenoid glenoid plane and normals

    load('glenoid_idx_lower.mat')

    glenoid_stl.Points = scapula_stl.Points(glenoid_lower_idx,:);

    % Fit plane to glenoid points. This is not the "true" glenoid plane as
    % that is calculated from the LS sphere later

    % Linear Regression method to fit plane
    x_gl = glenoid_stl.Points(:,1);
    y_gl = glenoid_stl.Points(:,2);
    z_gl = glenoid_stl.Points(:,3);

    DM = [x_gl, y_gl, ones(size(z_gl))];
    B = DM\z_gl;

    % Create meshgrid of plane from Linear Regresion
    [X,Y] = meshgrid(linspace(min(x_gl),max(x_gl),50), linspace(min(y_gl),max(y_gl),50));
    Z = B(1)*X + B(2)*Y + B(3)*ones(size(X));

    % Create point cloud Linear Regression plane (consistensy with following code)
    glenoid_plane_pointCloud = pointCloud([X(:), Y(:), Z(:)]);
    % Fit plane to the Linear Regresion plane points
    [glenoid_plane,~,~, ~] = pcfitplane(glenoid_plane_pointCloud, 0.0001, 'MaxNumTrials', 1e6);

    glenoid_barycentre = mean(glenoid_stl.Points);
    % Initial normal to correct for position of LS sphere
    glenoid_normal = glenoid_plane.Normal;

    [glenoid_normal, stl_scap] = checkGlenoidNorm(x, y, z, glenoid_normal, glenoid_barycentre);

    glenSphere_lsq.Radius = 0.030;

    % Initial guess - progection from center to 30 mm out
    x0 = glenoid_barycentre + glenoid_normal*0.030;
    x0(4) = glenSphere_lsq.Radius;

    [x_opt] = glenoidSphereFitLS(glenoid_stl, x0, glenoid_normal, glenoid_barycentre);
    glenSphere_lsq.Center = x_opt(1:3);
    glenSphere_lsq.Radius = x_opt(4);

    % Normalised radial line of LS sphere
    glenoid_normal = (glenSphere_lsq.Center - glenoid_barycentre)/norm(glenSphere_lsq.Center - glenoid_barycentre);
    % Redefine glenoid plane with LS normal at barycentre
    plane_delta = - sum(glenoid_normal.*glenoid_barycentre);
    glenoid_plane = planeModel([glenoid_normal plane_delta]);

    glenoid_plane_normals.z_p = glenoid_barycentre + R*glenoid_normal;
    scatter3(glenoid_plane_normals.z_p(1), glenoid_plane_normals.z_p(2), glenoid_plane_normals.z_p(3), 'filled', 'g', 'MarkerEdgeColor', 'black')

    % Generate sphere mesh
    [xs,ys,zs] = sphere(101);
    xs = xs*glenSphere_lsq.Radius(1);
    ys = ys*glenSphere_lsq.Radius(1);
    zs = zs*glenSphere_lsq.Radius(1);

    % Generate plane mesh using Ax + By + Gz + D = 0
    [gle_plane_mesh_data.x_plane, gle_plane_mesh_data.y_plane] = meshgrid(-0.1:0.01:0.1);
    gle_plane_mesh_data.z_plane = -1*(glenoid_plane.Parameters(1)*gle_plane_mesh_data.x_plane ...
        + glenoid_plane.Parameters(2)*gle_plane_mesh_data.y_plane ...
        + glenoid_plane.Parameters(4))/glenoid_plane.Parameters(3);

    hold on;

    surf(gle_plane_mesh_data.x_plane, gle_plane_mesh_data.y_plane, gle_plane_mesh_data.z_plane,...
        'FaceColor','b',...
        'FaceAlpha', 0.25,...
        'EdgeAlpha', 0)
    surf(xs+glenSphere_lsq.Center(1), ys+glenSphere_lsq.Center(2), zs+glenSphere_lsq.Center(3), 'EdgeColor','none', 'FaceColor','r', 'FaceAlpha', 0.1)
    scatter3(scapula_stl.Points(glenoid_lower_idx,1), scapula_stl.Points(glenoid_lower_idx,2), scapula_stl.Points(glenoid_lower_idx,3),'r')
    scatter3(glenSphere_lsq.Center(1), glenSphere_lsq.Center(2), glenSphere_lsq.Center(3), 'filled', 'r', 'MarkerEdgeColor','black')
    scatter3(glenoid_barycentre(1), glenoid_barycentre(2), glenoid_barycentre(3), 'filled', 'cyan')
    line([glenoid_barycentre(1) glenSphere_lsq.Center(1)], [glenoid_barycentre(2) glenSphere_lsq.Center(2)], [glenoid_barycentre(3) glenSphere_lsq.Center(3)],'Color', 'g', 'LineWidth', 4)

end

%% Calculate scapular plane
% scap_pointCloud = pointCloud([x(:), y(:), z(:)]);
    %work was not undertaken to replicate the contour method of the
    %BluePrint software...but could be integrated later as Aren has done
    %something like this.

% Linear Regression method to fit plane
x_sp = x(:);
y_sp = y(:);
z_sp = z(:);

DM = [x_sp, y_sp, ones(size(z_sp))];
B = DM\z_sp;

% Create meshgrid of plane from Linear Regresion
[X,Y] = meshgrid(linspace(min(x_sp),max(x_sp),50), linspace(min(y_sp),max(y_sp),50));
Z = B(1)*X + B(2)*Y + B(3)*ones(size(X));

% Create point cloud Linear Regression plane (consistensy with following code)
scap_plane_pointCloud = pointCloud([X(:), Y(:), Z(:)]);
% Fit plane to the Linear Regresion plane points
[scap_plane,~,~, ~] = pcfitplane(scap_plane_pointCloud, 0.0001, 'MaxNumTrials', 1e6);

% Generate plane mesh and plot using Ax + By + Gz + D = 0
[sca_plane_mesh_data.x_plane, sca_plane_mesh_data.y_plane] = meshgrid(-0.1:0.01:0.1);
sca_plane_mesh_data.z_plane = -1*(scap_plane.Parameters(1)*sca_plane_mesh_data.x_plane ...
    + scap_plane.Parameters(2)*sca_plane_mesh_data.y_plane ...
    + scap_plane.Parameters(4))/scap_plane.Parameters(3);

% figure;
% pcshow(scap_pointCloud, 'MarkerSize',20);
% hold on;
surf(sca_plane_mesh_data.x_plane, sca_plane_mesh_data.y_plane, sca_plane_mesh_data.z_plane,...
    'FaceColor','y',...
    'FaceAlpha', 0.25,...
    'EdgeAlpha', 0)

%% Calculate supraspinatus fossa base vector

load fossa_base.mat; %a list of SSM point indices manually defined as being the base of the fossa
principal_cmp = pca([x(fossa_base.vertices(:)), y(fossa_base.vertices(:)), z(fossa_base.vertices(:))]);
fossa_vector = principal_cmp(:,1)';
% Plot 1st principle component vector
% fossa_point_i = [x(fossa_base.vertices(9)), y(fossa_base.vertices(9)), z(fossa_base.vertices(9))];
% fossa_point_f = fossa_point_i + fossa_vector.*0.1;
fossa_point_f = glenoid_barycentre + fossa_vector.*R;
if flag_globalGlenoid == false && flag_global4LowerGlenoid == true
    fossa_point_f_global_glenoid = glenoid_barycentre_global + fossa_vector.*R;
end

% scatter3(x(fossa_base.vertices(:)), y(fossa_base.vertices(:)), z(fossa_base.vertices(:)), 'cyan', 'filled', 'MarkerEdgeColor', 'black');
% line([fossa_point_i(1) fossa_point_f(1)], [fossa_point_i(2) fossa_point_f(2)], [fossa_point_i(3) fossa_point_f(3)], 'LineWidth',4,'Color','cyan');
line([glenoid_barycentre(1) fossa_point_f(1)], [glenoid_barycentre(2) fossa_point_f(2)], [glenoid_barycentre(3) fossa_point_f(3)], 'LineWidth',4,'Color','cyan');
scatter3(fossa_point_f(1), fossa_point_f(2), fossa_point_f(3), 'filled', 'cyan', 'o','MarkerEdgeColor','black')


%% Project Points onto glenoid plane (minimisation problem)

% Glenoid barycentre onto glenoid plane
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% NOTE %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% This updates the value of glenoid_barycentre to the projection (x, y, z)
plane_parameters = glenoid_plane.Parameters;
% Constraint function (plane)
f_con = @(y_m)plane_func_d(y_m, plane_parameters);
options = optimset('MaxIter', 100, 'TolFun', 1e-4);
% Initial Condition (point on plane)
y_m_0 = [gle_plane_mesh_data.x_plane(1) gle_plane_mesh_data.y_plane(1) gle_plane_mesh_data.z_plane(1)];
% Cost function (distance)
J_barycentre = @(y_m)sqrt((glenoid_barycentre(1) - y_m(1))^2 + (glenoid_barycentre(2) - y_m(2))^2 + (glenoid_barycentre(3) - y_m(3))^2);
% Run fmincon
[glenoid_barycentre, ~] = fmincon(J_barycentre,...
    y_m_0,...
    [],...
    [],...
    [],...
    [],...
    [],...
    [],...
    f_con,...
    options);

scatter3(glenoid_barycentre(1), glenoid_barycentre(2), glenoid_barycentre(3), 'filled','o','magenta');

% Check if Barycentre sits on plane. Should be -> 0
bary_plane = glenoid_plane.Parameters(1)*glenoid_barycentre(1) +...
    glenoid_plane.Parameters(2)*glenoid_barycentre(2) +...
    glenoid_plane.Parameters(3)*glenoid_barycentre(3) + ...
    glenoid_plane.Parameters(4);



if bary_plane >= 1e-4
    disp('Error: Barycentre not sitting on plane')
    keyboard
end

%% Calculate vector of glenoid and scapula plane intersection
if flag_globalGlenoid == false && flag_global4LowerGlenoid == true  %this is special 'incorrection calculation' condition for Jaylan's study 
    %% Calculate glenoid normal from global glenoid surface 
    [~, intersect_v] = plane_intersect(glenoid_plane_global.Parameters(1:3),...
        [gle_plane_global_mesh_data.x_plane(1) gle_plane_global_mesh_data.y_plane(1) gle_plane_global_mesh_data.z_plane(1)],...
        scap_plane.Parameters(1:3),...
        [sca_plane_mesh_data.x_plane(1) sca_plane_mesh_data.y_plane(1) sca_plane_mesh_data.z_plane(1)]);

    % Normalise intersection vector
    intersect_v = intersect_v/norm(intersect_v);

    % Check for orientation of vector with respect to Y axis
    intersect_v_angle = vrrotvec([0 1 0], intersect_v);
    intersect_v_angle_deg = rad2deg(intersect_v_angle(4));

    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%% CHECK %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    % Check if plane norm and glenoid_inferior_on_plane are perpendicular
   
    if dot(intersect_v, glenoid_normal_global) < 1e-10
        % NEED to make sure axis is pointing superiorly
        if intersect_v_angle_deg < 90 && intersect_v_angle_deg > - 90
            glenoid_plane_y_n_global = intersect_v;
        else
            glenoid_plane_y_n_global = -intersect_v;
        end
    else
        disp(' Error: Glenoid plane Y and Z axes not perpendicular');
        keyboard
    end
    
    clear intersect_v

    %% Continue with calculation of lower glenoid glenoid plane and normals
    [~, intersect_v] = plane_intersect(glenoid_plane.Parameters(1:3),...
        [gle_plane_mesh_data.x_plane(1) gle_plane_mesh_data.y_plane(1) gle_plane_mesh_data.z_plane(1)],...
        scap_plane.Parameters(1:3),...
        [sca_plane_mesh_data.x_plane(1) sca_plane_mesh_data.y_plane(1) sca_plane_mesh_data.z_plane(1)]);

    % Normalise intersection vector
    intersect_v = intersect_v/norm(intersect_v);

    % Check for orientation of vector with respect to Y axis
    intersect_v_angle = vrrotvec([0 1 0], intersect_v);
    intersect_v_angle_deg = rad2deg(intersect_v_angle(4));

    % Plot Barycetntre where cup will be placed
    scatter3(glenoid_barycentre(1), glenoid_barycentre(2), glenoid_barycentre(3), 'black','filled','o')

    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%% CHECK %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    % Check if plane norm and glenoid_inferior_on_plane are perpendicular
   
    if dot(intersect_v, glenoid_normal) < 1e-10
        % NEED to make sure axis is pointing superiorly
        if intersect_v_angle_deg < 90 && intersect_v_angle_deg > - 90
            glenoid_plane_y_n = intersect_v;
        else
            glenoid_plane_y_n = -intersect_v;
        end
    else
        disp(' Error: Glenoid plane Y and Z axes not perpendicular');
        keyboard
    end

else  %this is used for the RSA angle 'correct' calculation in Jaylan's study and in the first study by Pavlos
    [~, intersect_v] = plane_intersect(glenoid_plane.Parameters(1:3),...
        [gle_plane_mesh_data.x_plane(1) gle_plane_mesh_data.y_plane(1) gle_plane_mesh_data.z_plane(1)],...
        scap_plane.Parameters(1:3),...
        [sca_plane_mesh_data.x_plane(1) sca_plane_mesh_data.y_plane(1) sca_plane_mesh_data.z_plane(1)]);

    % Normalise intersection vector
    intersect_v = intersect_v/norm(intersect_v);

    % Check for orientation of vector with respect to Y axis
    intersect_v_angle = vrrotvec([0 1 0], intersect_v);
    intersect_v_angle_deg = rad2deg(intersect_v_angle(4));

    % Plot Barycetntre where cup will be placed
    scatter3(glenoid_barycentre(1), glenoid_barycentre(2), glenoid_barycentre(3), 'black','filled','o')

    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%% CHECK %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    % Check if plane norm and glenoid_inferior_on_plane are perpendicular
   
    if dot(intersect_v, glenoid_normal) < 1e-10
        % NEED to make sure axis is pointing superiorly
        if intersect_v_angle_deg < 90 && intersect_v_angle_deg > - 90
            glenoid_plane_y_n = intersect_v;
        else
            glenoid_plane_y_n = -intersect_v;
        end
    else
        disp(' Error: Glenoid plane Y and Z axes not perpendicular');
        keyboard
    end
end
%% Handle hemisphere at glenoid plane

% Define depth/geometry of the "glenoid head" (phi<theta/4 for anything smaller than
% hemisphere)
theta = (0:0.01:1)*2*pi;
phi = (0:0.01:1)*pi/2;

% Need to rototranslate it so the the vertex is sitting on the point of
% interest
[THETA,PHI]=meshgrid(theta,phi);
X1=R.*cos(THETA).*sin(PHI) + glenoid_barycentre(1);
Y1=R.*sin(THETA).*sin(PHI) + glenoid_barycentre(2);
Z1=R.*cos(PHI) + glenoid_barycentre(3);

figure(10);
hemisphere_gle = surf(X1,Y1,Z1,...
    'FaceColor',[ 1 1 0],...
    'FaceAlpha', 0.75,...
    'EdgeColor', [0 0 0 ],...
    'EdgeAlpha', 0.1);
axis equal

% Quck workaround to rotate - Use the graphic object handler and then
% extract the point data X-Y-Z

% Find axis and angle of rotation between plane normal and where hemisphere
% is ploted about Z-axis [0 0 1]
glen_rot = vrrotvec([0 0 1], glenoid_normal);
% Rotate hemisphere about plane normal axis to aligned on plane out of
% plane normal

rotate(hemisphere_gle,glen_rot(1:3),rad2deg(glen_rot(4)), glenoid_barycentre)

% This is the Glenoid plane Y-axis
glenoid_plane_normals.y_p = glenoid_barycentre + R.*glenoid_plane_y_n(1:3);
scatter3(glenoid_plane_normals.y_p(1),glenoid_plane_normals.y_p(2), glenoid_plane_normals.y_p(3),'yellow','filled','o','MarkerEdgeColor','black')

line([glenoid_barycentre(1) glenoid_plane_normals.y_p(1)],...
    [glenoid_barycentre(2) glenoid_plane_normals.y_p(2)],...
    [glenoid_barycentre(3) glenoid_plane_normals.y_p(3)], ...
    'LineWidth',4,'Color','yellow');

%% Extract baseline parameters and data points for cup, plane and humerus
% Extract relevant data from hemisphere cup placed on resection barycentre
% and from there make positional changes as below.

glenoid_plane_normals.y_n = glenoid_plane_y_n; % Superior/inferior
glenoid_plane_normals.z_n = glenoid_normal; % Out of plane
glenoid_plane_normals.x_n = -cross(glenoid_plane_normals.z_n,glenoid_plane_normals.y_n); % Anterior/Posterior

if flag_globalGlenoid == false && flag_global4LowerGlenoid == true %again this is the 'incorrect' calculation method in Jaylan's paper described at top of this file
    glenoid_plane_normals.y_n_global = glenoid_plane_y_n_global;
    glenoid_plane_normals.z_n_global = glenoid_normal_global;
    glenoid_plane_normals.x_n_global = -cross(glenoid_plane_normals.z_n_global, glenoid_plane_normals.y_n_global); % Anterior/Posterior
end

% Plot axis of final norm from barycentre
glenoid_plane_normals.x_p = glenoid_barycentre + glenoid_plane_normals.x_n(1:3)*R;
scatter3(glenoid_plane_normals.x_p(1),glenoid_plane_normals.x_p(2), glenoid_plane_normals.x_p(3),'red','filled','o','MarkerEdgeColor','black')

line([glenoid_barycentre(1) glenoid_plane_normals.x_p(1)],...
    [glenoid_barycentre(2) glenoid_plane_normals.x_p(2)],...
    [glenoid_barycentre(3) glenoid_plane_normals.x_p(3)], ...
    'LineWidth',4,'Color','red');

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% CHECK %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Check they're mutually perpendicular
if dot(glenoid_plane_normals.x_n, glenoid_plane_normals.y_n ) > 1e-10 && ...
        dot(glenoid_plane_normals.y_n, glenoid_plane_normals.z_n) > 1e-10

    disp('Error: Plane normals not perpendicular')

    keyboard

end

% All displacements are defined on the glenoid plane now based on the
% variable: glenoid_plane_normals

%% Calculate version and inclination correction angles from fossa vector angle; And 12 mm rule from most inferior point on glenoid Y-axis

% Cache data from lower glenoid calculations in order to use global glenoid data then
% switch back to lower values in variables
if flag_globalGlenoid == false && flag_global4LowerGlenoid == true %again this is the 'incorrect' calculation method in Jaylan's paper described at top of this file
    
    glenoid_barycentre_cached = glenoid_barycentre;
    glenoid_barycentre = glenoid_barycentre_global;

    glenoid_plane_normals_cache.x_n = glenoid_plane_normals.x_n;
    glenoid_plane_normals_cache.y_n = glenoid_plane_normals.y_n;
    glenoid_plane_normals_cache.z_n = glenoid_plane_normals.z_n;

    glenoid_plane_normals.x_n = glenoid_plane_normals.x_n_global;
    glenoid_plane_normals.y_n = glenoid_plane_normals.y_n_global;
    glenoid_plane_normals.z_n = glenoid_plane_normals.z_n_global;

    fossa_point_f_cache = fossa_point_f;
    fossa_point_f = fossa_point_f_global_glenoid
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% Inclination %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% YZ %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% fossa_vector onto glenoid YZ plane (glenoid_plane_normals.x_n)
% Constraint function (plane)
delta = -sum(glenoid_barycentre.*glenoid_plane_normals.x_n);
plane_parameters = [glenoid_plane_normals.x_n delta];
f_con = @(y_m)plane_func_d(y_m, plane_parameters);
y_m_0 = glenoid_barycentre;
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% NOTE %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% This updates the value of glenoid_barycentre to the projection (x, y, z)
% Cost function (distance)
J_fossa_point_f = @(y_m)sqrt((fossa_point_f(1) - y_m(1))^2 + (fossa_point_f(2) - y_m(2))^2 + (fossa_point_f(3) - y_m(3))^2);
% Run fmincon
[fossa_point_f_YZ, ~] = fmincon(J_fossa_point_f,...
    y_m_0,...
    [],...
    [],...
    [],...
    [],...
    [],...
    [],...
    f_con,...
    options);

% Calculate Inclination correction angle

% Calculate unit vector from barycentre to projected point
fossa_correction_v.YZ = (fossa_point_f_YZ - glenoid_barycentre)/norm(fossa_point_f_YZ - glenoid_barycentre);
% Calcuate angle between correction angle about x_n
fossa_correction_ang.YZ = vrrotvec(glenoid_plane_normals.z_n, fossa_correction_v.YZ);
% Push correction vector point to R from barycentre
fossa_point_f_YZ = glenoid_barycentre + fossa_correction_v.YZ*R;

% Visualise Inclination angle
scatter3(fossa_point_f_YZ(1), fossa_point_f_YZ(2), fossa_point_f_YZ(3), 'filled','o','cyan', 'MarkerEdgeColor','black');
version_poly = [glenoid_barycentre; fossa_point_f_YZ; glenoid_plane_normals.z_p];
patch(version_poly(:,1), version_poly(:,2) , version_poly(:,3), 'r');
line([glenoid_barycentre(1) fossa_point_f_YZ(1)],...
    [glenoid_barycentre(2) fossa_point_f_YZ(2)],...
    [glenoid_barycentre(3) fossa_point_f_YZ(3)], ...
    'LineWidth',4,'Color','g');

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% Version %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% XZ %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% fossa_vector onto glenoid XZ plane (glenoid_plane_normals.y_n)
delta = -sum(glenoid_barycentre.*glenoid_plane_normals.y_n);
plane_parameters = [glenoid_plane_normals.y_n delta];
% Constraint function (plane)
f_con = @(y_m)plane_func_d(y_m, plane_parameters);
y_m_0 = glenoid_barycentre;
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% NOTE %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% This updates the value of glenoid_barycentre to the projection (x, y, z)
% Cost function (distance)
J_fossa_point_f = @(y_m)sqrt((fossa_point_f(1) - y_m(1))^2 + (fossa_point_f(2) - y_m(2))^2 + (fossa_point_f(3) - y_m(3))^2);
% Run fmincon
[fossa_point_f_XZ, ~] = fmincon(J_fossa_point_f,...
    y_m_0,...
    [],...
    [],...
    [],...
    [],...
    [],...
    [],...
    f_con,...
    options);

% Calculate Version correction angle

% Calculate unit vector from barycentre to projected point
fossa_correction_v.XZ = (fossa_point_f_XZ - glenoid_barycentre)/norm(fossa_point_f_XZ - glenoid_barycentre);
% Calcuate angle between correction angle about x_n
fossa_correction_ang.XZ = vrrotvec(glenoid_plane_normals.z_n, fossa_correction_v.XZ);
% Push correction vector point to R from barycentre
fossa_point_f_XZ = glenoid_barycentre + fossa_correction_v.XZ*R;

% Visualise Version angle
scatter3(fossa_point_f_XZ(1), fossa_point_f_XZ(2), fossa_point_f_XZ(3), 'filled','o','cyan', 'MarkerEdgeColor','black');
version_poly = [glenoid_barycentre; fossa_point_f_XZ; glenoid_plane_normals.z_p];
patch(version_poly(:,1), version_poly(:,2) , version_poly(:,3), 'y');
line([glenoid_barycentre(1) fossa_point_f_XZ(1)],...
    [glenoid_barycentre(2) fossa_point_f_XZ(2)],...
    [glenoid_barycentre(3) fossa_point_f_XZ(3)], ...
    'LineWidth',4,'Color','g');

% Return cached data from lower glenoid calculations to variables
if flag_globalGlenoid == false && flag_global4LowerGlenoid == true  %again this is the 'incorrect' calculation method in Jaylan's paper described at top of this file
    
    glenoid_barycentre = glenoid_barycentre_cached;

    glenoid_plane_normals.x_n = glenoid_plane_normals_cache.x_n;
    glenoid_plane_normals.y_n = glenoid_plane_normals_cache.y_n;
    glenoid_plane_normals.z_n = glenoid_plane_normals_cache.z_n;

    fossa_point_f = fossa_point_f_cache;

end

%%%%%%%%%%%%%%%%%%%%%%% Clean up correction angles %%%%%%%%%%%%%%%%%%%%%%%%
correction_angles.x_sup_inf_incl        = rad2deg(fossa_correction_ang.YZ(4));
correction_angles.y_ant_retro_version   = rad2deg(fossa_correction_ang.XZ(4));

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% NOTE %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% The following need to be done before any rotations so it correctly
% identifies inferior most point on the hemisphere from the rim
if flag_AthwalOr12mm == true

    %%%%%%%%%%%%%%%%%%%%%%%%%%% Athwal Rule %%%%%%%%%%%%%%%%%%%%%%%%%%%%
    % Project a point inferiorly along glenoid -ive Y-axis
    p_point = glenoid_barycentre-glenoid_plane_normals.y_n*R*2;

    % Get mesh data for the hemisphere from Visualisation Object.
    hemi_gle_mesh_data.X = hemisphere_gle.XData;
    hemi_gle_mesh_data.Y = hemisphere_gle.YData;
    hemi_gle_mesh_data.Z = hemisphere_gle.ZData;

    hemi_gle_points = [hemi_gle_mesh_data.X(:), hemi_gle_mesh_data.Y(:), hemi_gle_mesh_data.Z(:)];

    min_hemi_points = vecnorm((hemi_gle_points - p_point), 2 , 2);
    [~, inf_point_idx_hemi] = min(min_hemi_points);

    % Get smallest Euclidian distance of glenoid rim points from projected
    % point on -ive Y-axis. Not exact but close ennough.
    min_rim_points = vecnorm((glenoid_stl.Points - p_point), 2 , 2);
    [~, inf_point_idx_rim] = min(min_rim_points);

    % Calculate distances
    inf_point.rim = glenoid_stl.Points(inf_point_idx_rim, :);
    d_inferior.rim = norm(inf_point.rim - glenoid_barycentre);

    inf_point.hemisphere = hemi_gle_points(inf_point_idx_hemi, :);
    d_inferior.hemisphere =  norm(inf_point.hemisphere - inf_point.rim );

    correction_displacement.y_prox_dist = - overhang - d_inferior.hemisphere;

elseif flag_AthwalOr12mm == false

    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% 12 mm rule %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    % Get mesh data for the hemisphere from Visualisation Object. This will
    % then be continuesly updated through "hemisphere" Surface variable

    % Project a point inferiorly along glenoid -ive Y-axis
    p_point = glenoid_barycentre-glenoid_plane_normals.y_n*R*2;

    hemi_gle_mesh_data.X = hemisphere_gle.XData;
    hemi_gle_mesh_data.Y = hemisphere_gle.YData;
    hemi_gle_mesh_data.Z = hemisphere_gle.ZData;

    hemi_gle_points = [hemi_gle_mesh_data.X(:), hemi_gle_mesh_data.Y(:), hemi_gle_mesh_data.Z(:)];

    min_hemi_points = vecnorm((hemi_gle_points - p_point), 2 , 2);
    [~, inf_point_idx_hemi] = min(min_hemi_points);

    % Get smallest Euclidian distance of glenoid rim points from projected
    % point on -ive Y-axis. Not exact bur close ennough
    min_rim_points = vecnorm((glenoid_stl.Points - p_point), 2 , 2);
    [~, inf_point_idx_rim] = min(min_rim_points);

    % Calculate distances
    inf_point.rim = glenoid_stl.Points(inf_point_idx_rim, :);
    d_inferior.rim = norm(inf_point.rim - glenoid_barycentre);

    inf_point.hemisphere = hemi_gle_points(inf_point_idx_hemi, :);
    d_inferior.hemisphere =  norm(inf_point.hemisphere - inf_point.rim );

    correction_displacement.y_prox_dist = d_inferior.rim - 0.012;
    
end
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% NOTE %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% Prox/Dist %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%                                   &
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% Lateral Offset %%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Calculated after X and Y rotations are applied to the glenosphere because
% the glenoid plane (i.e. normal to glenosphere) is rotated

%% Change position of the cup

% 1) Position on resection surface (superior/inferior, anterior/posterior)
% 2) Offset from resection surface (lateralisation)
% 3) Version/Inclination

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% NOTE %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% The vector that will be rotated needs to be a column vector so it is
% transposed here (') then back again after rotations are finished
% Translate cup centre to originate from origin
CoR_glen = glenoid_barycentre;

%% Version/Inclination of cup about hemisphere normal axes

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% 1st Rotation %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% Supero-/Infero- inclination (about Anterior/Posterior axis)
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% NOTE %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% For this rotation it will be rotated about the new X axis after first Z
% rotation to keep topological meaning for the cup orientation. Can be
% thought of as the orientation of the cup as it sat on the resection plane
% and then rotated about first axes
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% NOTE %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
if flag_correctInclination == true
    % Set sup_inf_inclination to correction value calculated
    hemi_gle_offsets.x_sup_inf_incl = correction_angles.x_sup_inf_incl;
else
    % Negate (-) hemi_gle_offsets.x_sup_inf_incl so that positive is superior
    hemi_gle_offsets.x_sup_inf_incl = - hemi_gle_offsets.x_sup_inf_incl;
end

rotate(hemisphere_gle,...
    glenoid_plane_normals.x_n,...
    hemi_gle_offsets.x_sup_inf_incl,...
    glenoid_barycentre)

% Rotation matrix
R_x = axang2rotm([glenoid_plane_normals.x_n deg2rad(hemi_gle_offsets.x_sup_inf_incl)]);

% Rotate glenoid_plane_normals.y_n axis after second rotation
glenoid_plane_normals.y_n_r1 = R_x*glenoid_plane_normals.y_n';
glenoid_plane_normals.y_n_r1 = glenoid_plane_normals.y_n_r1';

glenoid_plane_normals.z_n_r1 = R_x*glenoid_plane_normals.z_n';
glenoid_plane_normals.z_n_r1 = glenoid_plane_normals.z_n_r1';

ppy = glenoid_barycentre + R*glenoid_plane_normals.y_n_r1;
scatter3(ppy(1), ppy(2), ppy(3), 'yellow', 'filled');

ppz = glenoid_barycentre + R*glenoid_plane_normals.z_n_r1;
scatter3(ppz(1), ppz(2), ppz(3), 'green', 'filled');

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% 2nd Rotation %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
if flag_correctVersion == true
    % Set ant_retro_version to correction value calculated
    hemi_gle_offsets.y_ant_retro_version = correction_angles.y_ant_retro_version;
end

% Antero-/Postero- version (about Proximal/Distal axis)
rotate(hemisphere_gle,...
    glenoid_plane_normals.y_n_r1,...
    hemi_gle_offsets.y_ant_retro_version,...
    glenoid_barycentre)

% Rotation matrix
R_y = axang2rotm([glenoid_plane_normals.y_n_r1 deg2rad(hemi_gle_offsets.y_ant_retro_version)]);
R_z = axang2rotm([glenoid_plane_normals.z_n_r1 deg2rad(hemi_gle_offsets.y_ant_retro_version)]);

% Need to rotate glenoid_plane_normals.x_n axis after first rotation
glenoid_plane_normals.x_n_r1 = R_y*glenoid_plane_normals.x_n';
glenoid_plane_normals.x_n_r1 = glenoid_plane_normals.x_n_r1';

glenoid_plane_normals.z_n_r2 = R_y*glenoid_plane_normals.z_n_r1';
glenoid_plane_normals.z_n_r2 = glenoid_plane_normals.z_n_r2';

ppx = glenoid_barycentre + R*glenoid_plane_normals.x_n_r1;
scatter3(ppx(1), ppx(2), ppx(3), 'red', 'filled');

ppz = glenoid_barycentre + R*glenoid_plane_normals.z_n_r2;
scatter3(ppz(1), ppz(2), ppz(3), 'green', 'filled');


% Get transformed axes orientation offsets from origin

% Final rotation matrix of glenosphere axes
RM = [glenoid_plane_normals.x_n_r1;...
    glenoid_plane_normals.y_n_r1;...
    glenoid_plane_normals.z_n_r2];

% Calculate euler angles of fianl RM in global
ZYX_Euler_ang = rotm2eul(RM, 'ZYX');

% Invert calcutated angles
glenoid_plane_normals.theta(1) = - ZYX_Euler_ang(3);
glenoid_plane_normals.theta(2) = - ZYX_Euler_ang(2);
glenoid_plane_normals.theta(3) = - ZYX_Euler_ang(1);

%% Calcuate offset of the rotated glenoid plane from inferior glenoid rim


% % % % %%%%%%%%%%%%%%%%%%%%%%%%%%%%%% Lateral Offset %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% % % %
% % % % % Calculate Plane parameters after rotations are applied (Ax+By+Cz+D=0)
% % % % delta = -(glenoid_plane_normals.z_n_r2(1)*CoR_glen(1) + glenoid_plane_normals.z_n_r2(2)*CoR_glen(2) + glenoid_plane_normals.z_n_r2(3)*CoR_glen(3));
% % % % plane_parameters = [glenoid_plane_normals.z_n_r2 delta];
% % % %
% % % % % Constraint function (plane)
% % % % f_con = @(y_m)plane_func_d(y_m, plane_parameters);
% % % % options = optimset('MaxIter', 100, 'TolFun', 1e-4);
% % % %
% % % % % Cost function (distance)
% % % % J_inferior = @(y_m)sqrt((glenoid_stl.Points(inf_point_idx_rim, 1) - y_m(1))^2 + (glenoid_stl.Points(inf_point_idx_rim, 2) - y_m(2))^2 + (glenoid_stl.Points(inf_point_idx_rim, 3) - y_m(3))^2);
% % % % % Initial Condition (point on plane)
% % % % y_m_0 = [gle_plane_mesh_data.x_plane(1) gle_plane_mesh_data.y_plane(1) gle_plane_mesh_data.z_plane(1)];
% % % %
% % % %
% % % % % Run fmincon
% % % % [rim_on_glenoid_plane, ~] = fmincon(J_inferior,...
% % % %     y_m_0,...
% % % %     [],...
% % % %     [],...
% % % %     [],...
% % % %     [],...
% % % %     [],...
% % % %     [],...
% % % %     f_con,...
% % % %     options);
% % % %
% % % % inf_point.rim_on_plane = rim_on_glenoid_plane;
% % % % % scatter3(rim_on_glenoid_plane(1), rim_on_glenoid_plane(2), rim_on_glenoid_plane(3), 'filled','o','red');
% % % %
% % % % lat_offset_i = norm( inf_point.rim - inf_point.rim_on_plane);
% % % % lat_offset_f = lat_offset_i + offset;
% % % % hemi_gle_offsets.z_base_off = lat_offset_f;

%% Calculate distal and lateral corrections used by Athwal from inferior point of glenoid rim
% Refresh XYZ of hemisphere data
hemi_gle_points = [hemisphere_gle.XData(:), hemisphere_gle.YData(:), hemisphere_gle.ZData(:)];
% Get inferior most point on updated hemisphere
inf_point.hemisphere = hemi_gle_points(inf_point_idx_hemi, :);
scatter3(inf_point.hemisphere(1), inf_point.hemisphere(2), inf_point.hemisphere(3), 'cyan','filled','MarkerEdgeColor', 'black')

% Project point distaly along new Y-axis by overhang amout from inferior
% rim point
pp_hang = inf_point.rim - glenoid_plane_normals.y_n_r1*overhang;
scatter3(pp_hang(1), pp_hang(2), pp_hang(3), 'filled', 'y', 'MarkerEdgeColor', 'black')
% Project point lateraly along new Z-axis by offset amout from inferior
% rim point projection
pp_hang_plus_offset = pp_hang + glenoid_plane_normals.z_n_r2*offset;
scatter3(pp_hang_plus_offset(1), pp_hang_plus_offset(2), pp_hang_plus_offset(3), 'filled', 'magenta', 'MarkerEdgeColor', 'black');

% Calculate vector between final offset point and inferior most hemisphere
% in GLOBAL and then transform it into GLENOID reference frames
correction_vector.in_global = pp_hang_plus_offset-inf_point.hemisphere;
correction_vector.in_glenoid = (RM*correction_vector.in_global')';

% Set transformed vector to offset values
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% NOTE %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Not applying correction to anterior/posterior (caused by non-allignment
% of inferior rim and hemisphere points)
% hemi_gle_offsets.x_ant_post = correction_vector.in_glenoid(1);

%% Position on glenoid surface (anterior/posterior, base offset, superior/inferior)

%%%%%%%%%%%%%%%%%%%%% X - Anterior / Posterior offsets %%%%%%%%%%%%%%%%%%%%
hemisphere_gle.XData = hemisphere_gle.XData + glenoid_plane_normals.x_n_r1(1)*hemi_gle_offsets.x_ant_post;
hemisphere_gle.YData = hemisphere_gle.YData + glenoid_plane_normals.x_n_r1(2)*hemi_gle_offsets.x_ant_post;
hemisphere_gle.ZData = hemisphere_gle.ZData + glenoid_plane_normals.x_n_r1(3)*hemi_gle_offsets.x_ant_post;

% Adjust barrycentre to now be Joint CoR
CoR_glen = CoR_glen + glenoid_plane_normals.x_n_r1*hemi_gle_offsets.x_ant_post;

%%%%%%%%%%%%%%%%%%%%%% Y - Proximal / Distal offsets %%%%%%%%%%%%%%%%%%%%%%
if flag_correctProxDist == true && flag_AthwalOr12mm == false
    hemi_gle_offsets.y_prox_dist = correction_displacement.y_prox_dist;
elseif flag_correctProxDist == true && flag_AthwalOr12mm == true
    hemi_gle_offsets.y_prox_dist = correction_vector.in_glenoid(2);
end

hemisphere_gle.XData = hemisphere_gle.XData + glenoid_plane_normals.y_n_r1(1)*hemi_gle_offsets.y_prox_dist;
hemisphere_gle.YData = hemisphere_gle.YData + glenoid_plane_normals.y_n_r1(2)*hemi_gle_offsets.y_prox_dist;
hemisphere_gle.ZData = hemisphere_gle.ZData + glenoid_plane_normals.y_n_r1(3)*hemi_gle_offsets.y_prox_dist;

% Adjust barrycentre to now be Joint CoR
CoR_glen = CoR_glen + glenoid_plane_normals.y_n_r1*hemi_gle_offsets.y_prox_dist;

%%%%%%%%%%%%%%%%%%%%%%%%%%% Z - Base offset %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
if flag_correctLateral == true && flag_AthwalOr12mm == true
    hemi_gle_offsets.z_base_off = correction_vector.in_glenoid(3) + hemi_gle_offsets.z_base_off;
end

hemisphere_gle.XData = hemisphere_gle.XData + glenoid_plane_normals.z_n_r2(1)*hemi_gle_offsets.z_base_off;
hemisphere_gle.YData = hemisphere_gle.YData + glenoid_plane_normals.z_n_r2(2)*hemi_gle_offsets.z_base_off;
hemisphere_gle.ZData = hemisphere_gle.ZData + glenoid_plane_normals.z_n_r2(3)*hemi_gle_offsets.z_base_off;

% Adjust barrycentre to now be Joint CoR
CoR_glen = CoR_glen + glenoid_plane_normals.z_n_r2*hemi_gle_offsets.z_base_off;

scatter3(CoR_glen(1),CoR_glen(2), CoR_glen(3),'magenta','filled','o','MarkerEdgeColor','black')

ppy = CoR_glen + R*glenoid_plane_normals.y_n_r1;
scatter3(ppy(1), ppy(2), ppy(3), 'yellow', 'filled','MarkerEdgeColor','black');

ppz = CoR_glen + R*glenoid_plane_normals.z_n_r2;
scatter3(ppz(1), ppz(2), ppz(3), 'green', 'filled','MarkerEdgeColor','black');
% % % keyboard
ppx = CoR_glen + R*glenoid_plane_normals.x_n_r1;
scatter3(ppx(1), ppx(2), ppx(3), 'red', 'filled','MarkerEdgeColor','black');

%% Create scapula/glenoid structure to output for manipulation

scapula = struct('glenoid_plane_normals', glenoid_plane_normals,... % x-y-z normal vectors and end-points
    'hemi_gle_mesh_data', hemi_gle_mesh_data,...                    % DEFAULT data for glenoid hemisphere on glenoid plane before any rototranslation
    'hemi_gle_offsets', hemi_gle_offsets,...                        % glenoid hemisphere rototranslation offsets
    'glenoid_barycentre', glenoid_barycentre,...                    % centre of DEFAULT hemisphere (CoR of joint effectivly - needs the hemi_gle_offsets translation only to be applied along normals)
    'hemisphere_gle', hemisphere_gle,...                            % rototranslated glenoid hemisphere
    'glenoid_plane', glenoid_plane,...                              % glenoid plane parameters
    'plane_mesh_data', sca_plane_mesh_data,...
    'R', R,...                                                      % hemisphere radius (m)
    'CoR_glen', CoR_glen,...                                        % adjusted barycentre now as CoR
    'stl_scap', stl_scap);

stlwrite_user(['..\OpenSim\In\Geometry\gle_' rhash '.stl'],...
    hemisphere_gle.XData,...
    hemisphere_gle.YData,...
    hemisphere_gle.ZData,...
    'mode','ascii',...
    'triangulation','f');


end

function data = loadpiv(input, kwargs)
%% Load .vc7 dataset by specified forder or filenames.
%% The function takes following arguments:
%   input:              [string array]      - folder path or filenames array
%   subfolders:         [1×1 logical]       - search files in subfolders
%   parallel:           [1×1 logical]       - parallel loading
%   components:         [char array]        - return a structure with specified fields
%% The function returns following results:
% data = 
%   struct with fields:
% 
%     x: [n×m double]
%     y: [n×m double]
%     u: [n×m×k×l double]
%     v: [n×m×k×l double]
% or
% data = 
%   struct with fields:
% 
%     x: [n×m double]
%     z: [n×m double]
%     u: [n×m×k×l double]
%     w: [n×m×k×l double]
%% Examples:
%% 1. Load velocity fields from specified folder:
% data = loadpiv('\LVExport\u25mps\y_00');
%% 2. Load velocity fields from specified folder with subfolders:
% data = loadpiv('\LVExport\u25mps\', subfolders = true);
%% 3. Load velocity fields by specified filenames:
% data = loadpiv(["\LVExport\u25mps\y_00\B0001.vc7", "\LVExport\u25mps\y_00\B0002.vc7"]);

    arguments
        input (:,:) string
        kwargs.subfolders (1,1) logical = false
        kwargs.parallel (1,1) logical = false
        kwargs.components (1,:) char {mustBeMember(kwargs.components, {'x-y,u-v', 'x-z,u-w'})} = 'x-z,u-w'
        kwargs.storefilenames logical = false
        kwargs.cast {mustBeMember(kwargs.cast, {'single', 'double'})} = 'double'
        kwargs.regexp (1,1) logical = false
    end

    if isscalar(input)
        if isfolder(input)
            kwargs.filenames = getfilenames(input, extension = '.vc7', subfolders = kwargs.subfolders);
        else
            if kwargs.regexp
                dr = dir(input);
                nf = numel(unique(arrayfun(@(x)string(x.folder),dr)));
                f = arrayfun(@(x)string(fullfile(x.folder,x.name)),dr);
                kwargs.filenames = reshape(f,[],nf);
            else
                kwargs.filenames = input;
            end
        end
    else
        kwargs.filenames = input;
    end

    sz = size(kwargs.filenames);

    % store loaded field size
    imx = readimx(char(kwargs.filenames(1, 1)));
    nx = imx.Nx; nz = imx.Ny;
    
    % build spatial grid
    [ax1, ax2] = meshgrid(1:nx, 1:nz); vel1 = zeros([nz, nx, sz]); vel2 = zeros([nz, nx, sz]);
    ax1 = ax1 * imx.ScaleX(1) * imx.Grid + imx.ScaleX(2);
    ax2 = ax2 * imx.ScaleY(1) * imx.Grid + imx.ScaleY(2);
    ax1 = cast(ax1, kwargs.cast);
    ax2 = cast(ax2, kwargs.cast);

    if kwargs.parallel
        parfor i = 1:prod(sz)
            imx = readimx(char(kwargs.filenames(i)));
            vel1(:, :, i) = imx.Data(:, 1:nz)' * sign(imx.ScaleX(1)) * imx.ScaleI(1);
            vel2(:, :, i) = imx.Data(:, nz+1:2*nz)' * sign(imx.ScaleY(1)) * imx.ScaleI(1);  
        end
    else
        for i = 1:prod(sz)
            imx = readimx(char(kwargs.filenames(i)));
            vel1(:, :, i) = imx.Data(:, 1:nz)' * sign(imx.ScaleX(1)) * imx.ScaleI(1);
            vel2(:, :, i) = imx.Data(:, nz+1:2*nz)' * sign(imx.ScaleY(1)) * imx.ScaleI(1);  
        end
    end

    vel1 = reshape(vel1, [size(vel1, [1, 2]), sz]);
    vel2 = reshape(vel2, [size(vel2, [1, 2]), sz]);

    vel1 = cast(vel1, kwargs.cast);
    vel2 = cast(vel2, kwargs.cast);

    switch kwargs.components
        case 'x-y,u-v'
            data.x = ax1; data.y = ax2; data.u = vel1; data.v = vel2;
        case 'x-z,u-w'
            data.x = ax1; data.z = ax2; data.u = vel1; data.w = vel2;
    end

    if kwargs.storefilenames
        data.filenames = kwargs.filenames;
    end
end
%% 1D data, center, power
n = 1024*50;
t = linspace(0, 1, n);
fs = 1/(t(2)-t(1));
f1 = 500;
x = sin(t*2*pi*f1);

[spec, f] = procspecn(x(:),winlen=1024,overlap=512, ...
    winfun='hanning',norm=true,fs=fs,side='single',type='power',center=true,avg=true);

% Parcevall identity
[sqrt(sum(spec)), rms(x(:)), sqrt(sum(spec))./rms(x(:))]

cellplot('plot',{t(:),f},{x(:),spec},xlabel={'t, s','f, Hz'},ylabel={'x','S_{xx}'},...
    xscale={'linear','log'},yscale={'linear','log'},xlim={[0,1/f1],'auto'});
%% 1D data, center, PSD
n = 1024*50;
t = linspace(0, 1, n);
fs = 1/(t(2)-t(1));
f1 = 500;
x = sin(t*2*pi*f1);

[spec, f] = procspecn(x(:),winlen=1024,overlap=512, ...
    winfun='hanning',norm=true,fs=fs,side='single',type='psd',center=true,avg=true);
df = f(2) - f(1);

% Parcevall identity
[sqrt(sum(spec)*df), rms(x(:)), sqrt(sum(spec)*df)./rms(x(:))]

cellplot('plot',{t(:),f},{x(:),spec},xlabel={'t, s','f, Hz'},ylabel={'x','S_{xx}'},...
    xscale={'linear','log'},yscale={'linear','log'},xlim={[0,1/f1],'auto'});
%% 1D data, offset, power
n = 1024*50;
t = linspace(0, 1, n);
fs = 1/(t(2)-t(1));
f1 = 500;
x = sin(t*2*pi*f1)+2;

[spec, f] = procspecn(x(:),winlen=1024,overlap=512, ...
    winfun='hanning',norm=true,fs=fs,side='single',type='power',center=true,avg=true);

% Parcevall identity
[sqrt(sum(spec)), sqrt(var(x(:))), sqrt(sum(spec))./sqrt(var(x(:)))]

cellplot('plot',{t(:),f},{x(:),spec},xlabel={'t, s','f, Hz'},ylabel={'x','S_{xx}'},...
    xscale={'linear','log'},yscale={'linear','log'},xlim={[0,1/f1],'auto'});
%% 1D data, offset, PSD
n = 1024*50;
t = linspace(0, 1, n);
fs = 1/(t(2)-t(1));
f1 = 500;
x = sin(t*2*pi*f1)+2;

[spec, f] = procspecn(x(:),winlen=1024,overlap=512, ...
    winfun='hanning',norm=true,fs=fs,side='single',type='psd',center=true,avg=true);
df = f(2) - f(1);

% Parcevall identity
[sqrt(sum(spec)*df), sqrt(var(x(:))), sqrt(sum(spec)*df)./sqrt(var(x(:)))]

cellplot('plot',{t(:),f},{x(:),spec},xlabel={'t, s','f, Hz'},ylabel={'x','S_{xx}'},...
    xscale={'linear','log'},yscale={'linear','log'},xlim={[0,1/f1],'auto'});
%% 2D data
n = [1024*1, 1024*1];
[x, y] = meshgrid(linspace(0,1,n(1)),linspace(0,1,n(2)));
fs = 1./[x(2,2)-x(1,1),y(2,2)-y(1,1)];

f1 = [30, 15];
z = sin(x*2*pi*f1(1)+y*2*pi*f1(2));
tic
[spec, f] = procspecn(z,winlen=[64,64],overlap=[32,32], ...
    winfun='hanning',norm=true,fs=fs,side='single',type='power',center=true,avg=true);
toc
cellplot('contour',{x,f{1}},{y,f{2}},{z,spec},xlabel={'x, m','k_x, m^{-1}'},ylabel={'y, m','k_y, m^{-1}'},...
    xscale='linear',yscale='linear',xlim={[0,1/f1(1)],'auto'},ylim={[0,1/f1(2)],'auto'},colorbar='on',...
    clabel={'z','S_{zz}'},axis='equal');
%%
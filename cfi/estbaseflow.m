function estbaseflow(input, x0, z0, u0, k, param)
    %% Estimate component velocity distributions along proper axex of swept plate.

    %% Example:
    % u0 = 25;
    % k = [1/1.08, 1/1.08];
    % x0 = [280, 370]; z0 = [128, 170];
    % base_flow_estimate(pathes, x0, z0, u0, k);

    arguments
        input {mustBeA(input, {'string', 'char', 'struct'})}
        x0 (1,:) double % streamline origin x
        z0 (1,:) double % streamline origin z
        u0 (1,1) double % incoming flow velocity
        k (1,:) double % incoming flow velocity
        param.step (1,1) double = 1
    end

    load(fullfile(fileparts(mfilename('fullpath')), 'designed_base_flow.mat'));

    %% load data

    if isa(input, 'string')
        data = struct('x', [], 'z', [], 'u', [], 'w', [], 'u0', u0, 'k', k, 'label', "");
        for i = 1:length(input)
            temporary = loadpiv(input(i));
            data.x = cat(3, data.x, temporary.x); data.z = cat(3, data.z, temporary.z);
            data.u = cat(3, data.u, temporary.u); data.w = cat(3, data.w, temporary.w);
            [~, label, ~] = fileparts(input(i));
            data.label(i) = num2str(i);
        end
    else
        data = input;
        data.u0 = u0;
        data.k = k;
        data.label = "data";
    end
    
    clear temp; data.U = sqrt(data.u.^2+data.w.^2);
    
    %% linearinterp
    for i = 1:size(data.x, 3)
        data.uf{i} = fit([reshape(data.x(:, :, i), [], 1), reshape(data.z(:, :, i), [], 1)], ...
            reshape(data.u(:, :, i), [], 1), 'linearinterp');
        data.wf{i} = fit([reshape(data.x(:, :, i), [], 1), reshape(data.z(:, :, i), [], 1)], ...
            reshape(data.w(:, :, i), [], 1), 'linearinterp');
        data.Uf{i} = fit([reshape(data.x(:, :, i), [], 1), reshape(data.z(:, :, i), [], 1)], ...
            reshape(data.U(:, :, i), [], 1), 'linearinterp');
    end

    %% streamline
    for i = 1:size(data.x, 3)
        temp = streamline(data.x(:, :, i), data.z(:, :, i), data.u(:, :, i), data.w(:, :, i), x0(i), z0(i));
        data.xl{i} = temp.XData(1:param.step:end); data.zl{i} = temp.YData(1:param.step:end); 
        data.ul{i} = data.uf{i}(data.xl{i}, data.zl{i});
        data.wl{i} = data.wf{i}(data.xl{i}, data.zl{i});
        data.Ul{i} = data.Uf{i}(data.xl{i}, data.zl{i});
    end

    %% plot U(x, z)
    figure('WindowStyle', 'docked'); tiledlayout('flow');
    for i = 1:size(data.x, 3)
        nexttile; hold on; grid on; box on; axis equal;
        contourf(data.x(:, :, i), data.z(:, :, i), data.U(:, :, i), 50, 'LineStyle', 'None')
        clim([10, 50]);
        plot(data.xl{i}, data.zl{i})
        xlabel('x, mm'); ylabel('z, mm')
        clb = colorbar; ylabel(clb, '(u^2+w^2)^0.5, m/s');
        title(data.label(i), 'FontWeight', 'Normal')
    end
    %% plot u(x), v(x), U(x)
    figure('WindowStyle', 'docked'); hold on; grid on; box on; pbaspect([1, 1, 1]);
    xlabel('x, mm');
    for i = 1:size(data.x, 3)
        plot(data.xl{i}, data.ul{i}./data.u0*data.k(i), '.-', 'Color', [0 0.4470 0.7410], 'DisplayName', 'u/U_0')
        plot(data.xl{i}, data.wl{i}./data.u0*data.k(i), '.-', 'Color', [0.8500 0.3250 0.0980], 'DisplayName', 'w/U_0')
        plot(data.xl{i}, data.Ul{i}./data.u0*data.k(i), '.-', 'Color', [0.4660 0.6740 0.1880], 'DisplayName', '(u^{2}+w^{2})^{1/2}/U_{0}')
    end
    
    plot(x_prime*1e3, u_prime, 'Color', [0 0.4470 0.7410], 'DisplayName', 'u/U_{0}')
    plot(x_prime*1e3, v_prime, 'Color', [0.8500 0.3250 0.0980], 'DisplayName', 'w/U_{0}')
    plot(x_prime*1e3, sqrt(u_prime.^2+v_prime.^2), 'Color', [0.4660 0.6740 0.1880], 'DisplayName', '(u^{2}+w^{2})^{1/2}/U_{0}')
    
    title(strcat('k=', num2str(k)), 'FontWeight', 'normal');

    lgd = legend('Location', 'EastOutSide');
end
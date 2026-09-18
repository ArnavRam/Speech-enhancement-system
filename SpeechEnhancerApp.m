classdef SpeechEnhancerApp < handle
%SPEECHENHANCERAPP  Atlas - Speech Enhancement Toolkit (MATLAB R2021a+).
%   Simple, demo-first UI. Two tabs:
%     * Enhance         - record / load / enhance / compare / save
%     * LMS Comparison  - secondary adaptive-filter demonstration
%
%   All heavy lifting is done by the +dsp package. The main tab exposes
%   only user-meaningful controls; DSP parameters live behind the
%   "Advanced..." dialog and have sensible defaults so the user never
%   has to touch them.
%
%   Launch:
%       >> app = SpeechEnhancerApp;

    % ---------------- Palette (light theme, projector-friendly) ---------
    properties (Constant, Access = private)
        CLR_BG       = [0.965 0.968 0.976]
        CLR_CARD     = [1.000 1.000 1.000]
        CLR_TEXT     = [0.121 0.145 0.180]
        CLR_MUTED    = [0.420 0.450 0.500]
        CLR_HAIR     = [0.870 0.885 0.910]
        CLR_PRIMARY  = [0.180 0.490 0.980]   % Enhance button
        CLR_DANGER   = [0.886 0.242 0.242]   % Record button
        CLR_NEUTRAL  = [0.870 0.885 0.910]   % Stop button (disabled look)
        CLR_ACCENT   = [0.086 0.639 0.290]   % positive metric colour
        CLR_HEADER   = [0.078 0.102 0.145]
        CLR_SPEC     = 'parula'
    end

    % ---------------- Handles -------------------------------------------
    properties (Access = private)
        UIFigure          matlab.ui.Figure
        TabGroup          matlab.ui.container.TabGroup

        % Enhance tab
        TabEnhance        matlab.ui.container.Tab
        LblTitle          matlab.ui.control.Label
        LblSubtitle       matlab.ui.control.Label
        BtnAdvanced       matlab.ui.control.Button
        BtnRecord         matlab.ui.control.Button
        BtnStop           matlab.ui.control.Button
        BtnLoad           matlab.ui.control.Button
        LblLevel          matlab.ui.control.Label
        BtnEnhance        matlab.ui.control.Button
        BtnPlayOrig       matlab.ui.control.Button
        BtnPlayEnh        matlab.ui.control.Button
        BtnSaveEnh        matlab.ui.control.Button
        AxWaveOrig        matlab.ui.control.UIAxes
        AxWaveEnh         matlab.ui.control.UIAxes
        AxSpecOrig        matlab.ui.control.UIAxes
        AxSpecEnh         matlab.ui.control.UIAxes
        Metric1Value      matlab.ui.control.Label
        Metric2Value      matlab.ui.control.Label
        Metric3Value      matlab.ui.control.Label
        LblStatus         matlab.ui.control.Label

        % LMS tab
        TabLMS            matlab.ui.container.Tab
        BtnLmsRun         matlab.ui.control.Button
        BtnLmsPlayIn      matlab.ui.control.Button
        BtnLmsPlayOut     matlab.ui.control.Button
        SldLmsSNR         matlab.ui.control.Slider
        SldLmsMu          matlab.ui.control.Slider
        SldLmsLen         matlab.ui.control.Slider
        LblLmsSNR         matlab.ui.control.Label
        LblLmsMu          matlab.ui.control.Label
        LblLmsLen         matlab.ui.control.Label
        AxLmsPrimary      matlab.ui.control.UIAxes
        AxLmsError        matlab.ui.control.UIAxes
        AxLmsMse          matlab.ui.control.UIAxes
        LblLmsStatus      matlab.ui.control.Label

        % Runtime state
        Recorder
        LevelTimer
        Fs         double = 16000
        Original   double = []
        Enhanced   double = []
        Info       struct = struct()
        PlayerOrig
        PlayerEnh
        LmsPrimary double = []
        LmsError   double = []
        LmsClean   double = []
        LmsPlayerIn
        LmsPlayerOut

        % Advanced (persist across dialog opens)
        AdvOpts    struct = struct( ...
            'algorithm',    'wiener', ...
            'oversub',      2.0, ...
            'floorDb',      -15, ...
            'alphaDD',      0.98, ...
            'bootstrapSec', 1.5)
    end

    % =====================================================================
    methods (Access = public)
        function app = SpeechEnhancerApp()
            addpath(fileparts(mfilename('fullpath')));
            app.buildUI();
        end

        function delete(app)
            app.stopLevelTimer();
            if ~isempty(app.Recorder) && isvalid(app.Recorder)
                try, stop(app.Recorder); catch, end
            end
            if ~isempty(app.UIFigure) && isvalid(app.UIFigure)
                delete(app.UIFigure);
            end
        end
    end

    % =====================================================================
    %  UI construction
    % =====================================================================
    methods (Access = private)
        function buildUI(app)
            app.UIFigure = uifigure( ...
                'Name', 'Atlas - Speech Enhancement Toolkit', ...
                'Position', [80 80 1280 800], ...
                'Color', app.CLR_BG, ...
                'CloseRequestFcn', @(~,~) delete(app));

            app.TabGroup = uitabgroup(app.UIFigure, ...
                'Position', [0 0 1280 800]);

            app.buildEnhanceTab();
            app.buildLmsTab();
        end

        function buildEnhanceTab(app)
            app.TabEnhance = uitab(app.TabGroup, 'Title', 'Enhance', ...
                'BackgroundColor', app.CLR_BG);

            root = uigridlayout(app.TabEnhance, [6, 1]);
            root.RowHeight   = {70, 76, 68, '3x', '4x', 100};
            root.ColumnWidth = {'1x'};
            root.Padding     = [24 20 24 20];
            root.RowSpacing  = 14;
            root.BackgroundColor = app.CLR_BG;

            % ---------- 1. Header ----------
            header = uipanel(root, ...
                'BorderType', 'none', ...
                'BackgroundColor', app.CLR_BG);
            header.Layout.Row = 1;
            hg = uigridlayout(header, [2, 2]);
            hg.RowHeight   = {'fit', 'fit'};
            hg.ColumnWidth = {'1x', 'fit'};
            hg.Padding = [0 0 0 0]; hg.RowSpacing = 2;
            hg.BackgroundColor = app.CLR_BG;

            app.LblTitle = uilabel(hg, ...
                'Text', 'Atlas   -   Speech Enhancer', ...
                'FontSize', 22, 'FontWeight', 'bold', ...
                'FontColor', app.CLR_HEADER);
            app.LblTitle.Layout.Row = 1; app.LblTitle.Layout.Column = 1;

            app.BtnAdvanced = uibutton(hg, ...
                'Text', 'Advanced...', ...
                'FontSize', 12, ...
                'BackgroundColor', app.CLR_CARD, ...
                'FontColor', app.CLR_MUTED, ...
                'ButtonPushedFcn', @(~,~) app.openAdvanced());
            app.BtnAdvanced.Layout.Row = [1 2]; app.BtnAdvanced.Layout.Column = 2;

            app.LblSubtitle = uilabel(hg, ...
                'Text', 'Record or load noisy audio, then press Enhance.', ...
                'FontSize', 13, 'FontColor', app.CLR_MUTED);
            app.LblSubtitle.Layout.Row = 2; app.LblSubtitle.Layout.Column = 1;

            % ---------- 2. Input row (record / stop / load + level) ----
            inputCard = app.makeCard(root);
            inputCard.Layout.Row = 2;
            ig = uigridlayout(inputCard, [1, 5]);
            ig.RowHeight   = {'1x'};
            ig.ColumnWidth = {130, 130, 160, '1x', 220};
            ig.Padding = [16 12 16 12]; ig.ColumnSpacing = 10;
            ig.BackgroundColor = app.CLR_CARD;

            app.BtnRecord = app.bigButton(ig, 'Record', app.CLR_DANGER,  'w');
            app.BtnRecord.ButtonPushedFcn = @(~,~) app.onRecord();

            app.BtnStop   = app.bigButton(ig, 'Stop', app.CLR_NEUTRAL, app.CLR_TEXT);
            app.BtnStop.Enable = 'off';
            app.BtnStop.ButtonPushedFcn = @(~,~) app.onStop();

            app.BtnLoad   = app.bigButton(ig, 'Load audio', app.CLR_CARD, app.CLR_TEXT);
            app.BtnLoad.ButtonPushedFcn = @(~,~) app.onLoad();

            uilabel(ig, 'Text', '');   % flexible spacer

            app.LblLevel = uilabel(ig, ...
                'Text', 'Mic level:  idle', ...
                'FontName', 'Consolas', 'FontSize', 12, ...
                'FontColor', app.CLR_MUTED, ...
                'HorizontalAlignment', 'right');

            % ---------- 3. Action row (Enhance / Play / Save) ----------
            actCard = app.makeCard(root);
            actCard.Layout.Row = 3;
            ag = uigridlayout(actCard, [1, 5]);
            ag.RowHeight   = {'1x'};
            ag.ColumnWidth = {260, '1x', 170, 170, 170};
            ag.Padding = [16 10 16 10]; ag.ColumnSpacing = 10;
            ag.BackgroundColor = app.CLR_CARD;

            app.BtnEnhance = app.bigButton(ag, 'ENHANCE', app.CLR_PRIMARY, 'w');
            app.BtnEnhance.FontSize = 15;
            app.BtnEnhance.Enable = 'off';
            app.BtnEnhance.ButtonPushedFcn = @(~,~) app.onProcess();

            uilabel(ag, 'Text', '');

            app.BtnPlayOrig = app.bigButton(ag, 'Play original',  app.CLR_CARD, app.CLR_TEXT);
            app.BtnPlayOrig.Enable = 'off';
            app.BtnPlayOrig.ButtonPushedFcn = @(~,~) app.onPlayOriginal();

            app.BtnPlayEnh  = app.bigButton(ag, 'Play enhanced',  app.CLR_ACCENT, 'w');
            app.BtnPlayEnh.Enable = 'off';
            app.BtnPlayEnh.ButtonPushedFcn = @(~,~) app.onPlayEnhanced();

            app.BtnSaveEnh  = app.bigButton(ag, 'Save enhanced', app.CLR_CARD, app.CLR_TEXT);
            app.BtnSaveEnh.Enable = 'off';
            app.BtnSaveEnh.ButtonPushedFcn = @(~,~) app.onSave();

            % ---------- 4. Waveforms row ------------------------------
            waveCard = app.makeCard(root);
            waveCard.Layout.Row = 4;
            wg = uigridlayout(waveCard, [1, 2]);
            wg.ColumnWidth = {'1x', '1x'};
            wg.Padding = [10 8 10 8]; wg.ColumnSpacing = 14;
            wg.BackgroundColor = app.CLR_CARD;

            app.AxWaveOrig = uiaxes(wg);
            app.styleAxes(app.AxWaveOrig, 'Original waveform', 'time (s)', '');
            app.AxWaveEnh  = uiaxes(wg);
            app.styleAxes(app.AxWaveEnh,  'Enhanced waveform', 'time (s)', '');

            % ---------- 5. Spectrograms row ---------------------------
            specCard = app.makeCard(root);
            specCard.Layout.Row = 5;
            sg = uigridlayout(specCard, [1, 2]);
            sg.ColumnWidth = {'1x', '1x'};
            sg.Padding = [10 8 10 8]; sg.ColumnSpacing = 14;
            sg.BackgroundColor = app.CLR_CARD;

            app.AxSpecOrig = uiaxes(sg);
            app.styleAxes(app.AxSpecOrig, 'Original spectrogram', 'time (s)', 'Hz');
            app.AxSpecEnh  = uiaxes(sg);
            app.styleAxes(app.AxSpecEnh,  'Enhanced spectrogram', 'time (s)', 'Hz');

            % ---------- 6. Metric cards + status ----------------------
            bot = uipanel(root, 'BorderType', 'none', ...
                'BackgroundColor', app.CLR_BG);
            bot.Layout.Row = 6;
            bg = uigridlayout(bot, [1, 4]);
            bg.RowHeight   = {'1x'};
            bg.ColumnWidth = {'1x', '1x', '1x', '2x'};
            bg.Padding = [0 0 0 0]; bg.ColumnSpacing = 12;
            bg.BackgroundColor = app.CLR_BG;

            [~, app.Metric1Value] = app.metricCard(bg, 'Noise reduction', '--', app.CLR_ACCENT);
            [~, app.Metric2Value] = app.metricCard(bg, 'Duration',        '--', app.CLR_HEADER);
            [~, app.Metric3Value] = app.metricCard(bg, 'Method',          '--', app.CLR_HEADER);

            statusCard = app.makeCard(bg);
            stg = uigridlayout(statusCard, [1, 1]);
            stg.Padding = [14 8 14 8]; stg.BackgroundColor = app.CLR_CARD;
            app.LblStatus = uilabel(stg, ...
                'Text', 'Ready. Load a file or press Record. A brief pause before speaking gives the best result but is not required.', ...
                'FontColor', app.CLR_TEXT, 'WordWrap', 'on', 'FontSize', 12);
        end

        function buildLmsTab(app)
            app.TabLMS = uitab(app.TabGroup, 'Title', 'LMS Comparison', ...
                'BackgroundColor', app.CLR_BG);

            root = uigridlayout(app.TabLMS, [3, 3]);
            root.RowHeight   = {'1x', '1x', 'fit'};
            root.ColumnWidth = {320, '1x', '1x'};
            root.Padding = [24 20 24 20]; root.RowSpacing = 12; root.ColumnSpacing = 12;
            root.BackgroundColor = app.CLR_BG;

            ctrl = app.makeCard(root);
            ctrl.Layout.Row = [1 2]; ctrl.Layout.Column = 1;
            cg = uigridlayout(ctrl, [12, 2]);
            cg.RowHeight = repmat({'fit'}, 1, 12);
            cg.Padding = [14 14 14 14]; cg.RowSpacing = 6;
            cg.BackgroundColor = app.CLR_CARD;

            hdr = uilabel(cg, ...
                'Text', 'Two-Microphone LMS  (simulated)', ...
                'FontSize', 15, 'FontWeight', 'bold', ...
                'FontColor', app.CLR_HEADER);
            hdr.Layout.Column = [1 2];
            desc = uilabel(cg, ...
                'Text', ['A reference mic sees noise-only; a primary mic sees ' ...
                         'speech plus a filtered version of that noise. LMS learns ' ...
                         'the filter and cancels the noise. The residual is the ' ...
                         'enhanced speech.'], ...
                'WordWrap', 'on', 'FontColor', app.CLR_MUTED);
            desc.Layout.Column = [1 2];

            app.LblLmsSNR = uilabel(cg, 'Text', 'Input SNR: 0 dB', ...
                'FontColor', app.CLR_TEXT);
            app.LblLmsSNR.Layout.Column = [1 2];
            app.SldLmsSNR = uislider(cg, 'Limits', [-10 15], 'Value', 0, ...
                'ValueChangedFcn', @(~,~) app.updateLmsLabels());
            app.SldLmsSNR.Layout.Column = [1 2];

            app.LblLmsMu = uilabel(cg, 'Text', 'Step size mu: 0.10', ...
                'FontColor', app.CLR_TEXT);
            app.LblLmsMu.Layout.Column = [1 2];
            app.SldLmsMu = uislider(cg, 'Limits', [0.005 0.5], 'Value', 0.10, ...
                'ValueChangedFcn', @(~,~) app.updateLmsLabels());
            app.SldLmsMu.Layout.Column = [1 2];

            app.LblLmsLen = uilabel(cg, 'Text', 'Filter length: 64 taps', ...
                'FontColor', app.CLR_TEXT);
            app.LblLmsLen.Layout.Column = [1 2];
            app.SldLmsLen = uislider(cg, 'Limits', [8 256], 'Value', 64, ...
                'ValueChangedFcn', @(~,~) app.updateLmsLabels());
            app.SldLmsLen.Layout.Column = [1 2];

            app.BtnLmsRun = app.bigButton(cg, 'Run LMS', app.CLR_PRIMARY, 'w');
            app.BtnLmsRun.ButtonPushedFcn = @(~,~) app.onLmsRun();

            app.BtnLmsPlayIn = app.bigButton(cg, 'Play primary', app.CLR_CARD, app.CLR_TEXT);
            app.BtnLmsPlayIn.Enable = 'off';
            app.BtnLmsPlayIn.ButtonPushedFcn = @(~,~) app.onLmsPlayIn();

            app.BtnLmsPlayOut = app.bigButton(cg, 'Play enhanced (residual)', app.CLR_ACCENT, 'w');
            app.BtnLmsPlayOut.Layout.Column = [1 2];
            app.BtnLmsPlayOut.Enable = 'off';
            app.BtnLmsPlayOut.ButtonPushedFcn = @(~,~) app.onLmsPlayOut();

            app.LblLmsStatus = uilabel(cg, 'Text', 'Adjust parameters and press Run LMS.', ...
                'FontColor', app.CLR_MUTED, 'WordWrap', 'on');
            app.LblLmsStatus.Layout.Column = [1 2];

            p1 = app.makeCard(root);
            p1.Layout.Row = 1; p1.Layout.Column = [2 3];
            pg1 = uigridlayout(p1, [1 1]); pg1.Padding = [10 8 10 8];
            pg1.BackgroundColor = app.CLR_CARD;
            app.AxLmsPrimary = uiaxes(pg1);
            app.styleAxes(app.AxLmsPrimary, 'Primary mic (speech + noise)', 'time (s)', 'amp');

            p2 = app.makeCard(root);
            p2.Layout.Row = 2; p2.Layout.Column = [2 3];
            pg2 = uigridlayout(p2, [1 1]); pg2.Padding = [10 8 10 8];
            pg2.BackgroundColor = app.CLR_CARD;
            app.AxLmsError = uiaxes(pg2);
            app.styleAxes(app.AxLmsError, 'LMS residual (enhanced speech)', 'time (s)', 'amp');

            p3 = app.makeCard(root);
            p3.Layout.Row = 3; p3.Layout.Column = [1 3];
            pg3 = uigridlayout(p3, [1 1]); pg3.Padding = [10 8 10 8];
            pg3.BackgroundColor = app.CLR_CARD;
            app.AxLmsMse = uiaxes(pg3);
            app.styleAxes(app.AxLmsMse, 'Learning curve (EMA of squared error, dB)', ...
                'time (s)', 'MSE (dB)');
        end

        % ---------- UI primitives ---------------------------------------
        function p = makeCard(app, parent)
            p = uipanel(parent, ...
                'BackgroundColor', app.CLR_CARD, ...
                'BorderType', 'line', ...
                'ForegroundColor', app.CLR_HAIR, ...
                'HighlightColor',  app.CLR_HAIR);
        end

        function b = bigButton(app, parent, txt, bg, fg)
            b = uibutton(parent, ...
                'Text', txt, ...
                'BackgroundColor', bg, ...
                'FontColor', fg, ...
                'FontWeight', 'bold', ...
                'FontSize', 13);
        end

        function [card, valueLbl] = metricCard(app, parent, name, initialValue, valueColor)
            card = app.makeCard(parent);
            g = uigridlayout(card, [2, 1]);
            g.RowHeight = {'fit', 'fit'};
            g.Padding = [16 10 16 10]; g.RowSpacing = 2;
            g.BackgroundColor = app.CLR_CARD;

            nameLbl = uilabel(g, 'Text', upper(name), ...
                'FontSize', 10, 'FontWeight', 'bold', ...
                'FontColor', app.CLR_MUTED);
            nameLbl.Layout.Row = 1;

            valueLbl = uilabel(g, 'Text', initialValue, ...
                'FontSize', 20, 'FontWeight', 'bold', ...
                'FontColor', valueColor);
            valueLbl.Layout.Row = 2;
        end

        function styleAxes(app, ax, ttl, xl, yl)
            title(ax, ttl);
            xlabel(ax, xl); ylabel(ax, yl);
            ax.Color   = app.CLR_CARD;
            ax.XColor  = app.CLR_MUTED;
            ax.YColor  = app.CLR_MUTED;
            ax.GridColor = app.CLR_HAIR;
            ax.Title.Color = app.CLR_HEADER;
            ax.Title.FontWeight = 'bold';
            ax.FontSize = 11;
            ax.Box = 'off';
            grid(ax, 'on');
        end
    end

    % =====================================================================
    %  Advanced-settings dialog
    % =====================================================================
    methods (Access = private)
        function openAdvanced(app)
            d = uifigure('Name', 'Advanced settings', ...
                'Position', app.centeredDialogPos(460, 460), ...
                'Color', app.CLR_BG, ...
                'WindowStyle', 'modal', ...
                'Resize', 'off');

            g = uigridlayout(d, [12, 2]);
            g.RowHeight   = repmat({'fit'}, 1, 12);
            g.ColumnWidth = {'1x', '1x'};
            g.Padding = [20 20 20 20]; g.RowSpacing = 8;
            g.BackgroundColor = app.CLR_BG;

            hdr = uilabel(g, 'Text', 'Advanced settings', ...
                'FontSize', 16, 'FontWeight', 'bold', 'FontColor', app.CLR_HEADER);
            hdr.Layout.Column = [1 2];

            sub = uilabel(g, 'Text', ...
                ['Defaults are calibrated for typical noise. Only adjust if you ' ...
                 'know what you are doing.'], ...
                'FontColor', app.CLR_MUTED, 'WordWrap', 'on');
            sub.Layout.Column = [1 2];

            uilabel(g, 'Text', 'Algorithm', 'FontColor', app.CLR_TEXT);
            ddAlgo = uidropdown(g, ...
                'Items', {'Wiener (recommended)', 'Spectral Subtraction'}, ...
                'ItemsData', {'wiener', 'specsub'}, ...
                'Value', app.AdvOpts.algorithm);

            [lblOs, sldOs] = app.makeSliderRow(g, ...
                sprintf('Over-subtraction (spec-sub only): %.2f', app.AdvOpts.oversub), ...
                [0.5 3.0], app.AdvOpts.oversub);
            sldOs.ValueChangedFcn = @(s,~) set(lblOs, 'Text', ...
                sprintf('Over-subtraction (spec-sub only): %.2f', s.Value));

            [lblFl, sldFl] = app.makeSliderRow(g, ...
                sprintf('Spectral floor: %.0f dB', app.AdvOpts.floorDb), ...
                [-40 -6], app.AdvOpts.floorDb);
            sldFl.ValueChangedFcn = @(s,~) set(lblFl, 'Text', ...
                sprintf('Spectral floor: %.0f dB', s.Value));

            [lblDD, sldDD] = app.makeSliderRow(g, ...
                sprintf('Decision-directed smoothing: %.3f', app.AdvOpts.alphaDD), ...
                [0.90 0.995], app.AdvOpts.alphaDD);
            sldDD.ValueChangedFcn = @(s,~) set(lblDD, 'Text', ...
                sprintf('Decision-directed smoothing: %.3f', s.Value));

            [lblBt, sldBt] = app.makeSliderRow(g, ...
                sprintf('Bootstrap window: %.2f s', app.AdvOpts.bootstrapSec), ...
                [0.5 3.0], app.AdvOpts.bootstrapSec);
            sldBt.ValueChangedFcn = @(s,~) set(lblBt, 'Text', ...
                sprintf('Bootstrap window: %.2f s', s.Value));

            spacer = uilabel(g, 'Text', ''); spacer.Layout.Column = [1 2];

            btnReset = uibutton(g, 'Text', 'Reset defaults', ...
                'BackgroundColor', app.CLR_CARD, 'FontColor', app.CLR_MUTED);
            btnApply = uibutton(g, 'Text', 'Apply', ...
                'BackgroundColor', app.CLR_PRIMARY, 'FontColor', 'w', ...
                'FontWeight', 'bold');

            btnReset.ButtonPushedFcn = @(~,~) resetDefaults();
            btnApply.ButtonPushedFcn = @(~,~) applyAndClose();

            function resetDefaults()
                ddAlgo.Value  = 'wiener';
                sldOs.Value   = 2.0;   lblOs.Text = sprintf('Over-subtraction (spec-sub only): %.2f', 2.0);
                sldFl.Value   = -15;   lblFl.Text = sprintf('Spectral floor: %.0f dB', -15);
                sldDD.Value   = 0.98;  lblDD.Text = sprintf('Decision-directed smoothing: %.3f', 0.98);
                sldBt.Value   = 1.5;   lblBt.Text = sprintf('Bootstrap window: %.2f s', 1.5);
            end

            function applyAndClose()
                app.AdvOpts.algorithm    = ddAlgo.Value;
                app.AdvOpts.oversub      = sldOs.Value;
                app.AdvOpts.floorDb      = sldFl.Value;
                app.AdvOpts.alphaDD      = sldDD.Value;
                app.AdvOpts.bootstrapSec = sldBt.Value;
                delete(d);
            end
        end

        function [lbl, sld] = makeSliderRow(app, parent, text, lims, val)
            lbl = uilabel(parent, 'Text', text, 'FontColor', app.CLR_TEXT);
            lbl.Layout.Column = [1 2];
            sld = uislider(parent, 'Limits', lims, 'Value', val);
            sld.Layout.Column = [1 2];
        end

        function pos = centeredDialogPos(app, w, h)
            f = app.UIFigure.Position;
            pos = [f(1)+ (f(3)-w)/2, f(2)+(f(4)-h)/2, w, h];
        end
    end

    % =====================================================================
    %  Callbacks - Enhance tab
    % =====================================================================
    methods (Access = private)
        function onRecord(app)
            try
                app.Recorder = audiorecorder(app.Fs, 16, 1);
                record(app.Recorder);
                app.BtnRecord.Enable = 'off';
                app.BtnStop.Enable   = 'on';
                app.BtnLoad.Enable   = 'off';
                app.setStatus('Recording... a brief pause before speaking helps, but is not required. Press Stop when done.');
                app.startLevelTimer();
            catch ME
                app.setStatus(sprintf('Recorder error: %s', ME.message));
            end
        end

        function onStop(app)
            app.stopLevelTimer();
            if isempty(app.Recorder) || ~isvalid(app.Recorder), return; end
            stop(app.Recorder);
            x = getaudiodata(app.Recorder, 'double');
            app.setOriginal(x, app.Fs, 'live recording');
            app.BtnRecord.Enable = 'on';
            app.BtnStop.Enable   = 'off';
            app.BtnLoad.Enable   = 'on';
            app.LblLevel.Text    = 'Mic level:  idle';
        end

        function onLoad(app)
            [f, p] = uigetfile({'*.wav;*.flac;*.mp3;*.ogg', 'Audio files'}, ...
                'Select noisy audio');
            figure(app.UIFigure);
            if isequal(f, 0), return; end
            try
                [x, fs] = audioread(fullfile(p, f));
                if size(x, 2) > 1, x = mean(x, 2); end
                if fs ~= app.Fs, x = resample(x, app.Fs, fs); end
                app.setOriginal(x, app.Fs, f);
            catch ME
                app.setStatus(sprintf('Load failed: %s', ME.message));
            end
        end

        function setOriginal(app, x, fs, srcLabel)
            app.Original = x(:); app.Fs = fs; app.Enhanced = [];
            app.plotWave(app.AxWaveOrig, app.Original, app.Fs, 'Original waveform');
            app.plotSpec(app.AxSpecOrig, app.Original, app.Fs, 'Original spectrogram');
            cla(app.AxWaveEnh); title(app.AxWaveEnh, 'Enhanced waveform');
            cla(app.AxSpecEnh); title(app.AxSpecEnh, 'Enhanced spectrogram');
            app.Metric1Value.Text = '--';
            app.Metric2Value.Text = sprintf('%.2f s', numel(x)/fs);
            app.Metric3Value.Text = '--';
            app.BtnEnhance.Enable = 'on';
            app.BtnPlayOrig.Enable = 'on';
            app.BtnPlayEnh.Enable  = 'off';
            app.BtnSaveEnh.Enable  = 'off';
            app.setStatus(sprintf('Loaded %s  -  %.2f s @ %d Hz.  Press ENHANCE.', ...
                srcLabel, numel(x)/fs, fs));
        end

        function onProcess(app)
            if isempty(app.Original)
                app.setStatus('Load or record audio first.'); return;
            end
            adv = app.AdvOpts;
            opts = struct();
            opts.algorithm = adv.algorithm;
            opts.noise   = struct('bootstrapSec', adv.bootstrapSec);
            opts.wiener  = struct('alphaDD', adv.alphaDD, ...
                                  'Gmin',    10^(adv.floorDb/20));
            opts.specsub = struct('oversub', adv.oversub, ...
                                  'floor',   10^(adv.floorDb/10));

            app.setStatus('Processing...'); drawnow;
            try
                [y, info] = dsp.enhanceSpeech(app.Original, app.Fs, opts);
                app.Enhanced = y; app.Info = info;
                app.plotWave(app.AxWaveEnh, y, info.fs, 'Enhanced waveform');
                app.plotSpec(app.AxSpecEnh, y, info.fs, 'Enhanced spectrogram');

                m = senh.computeMetrics([], app.Original, y, info.fs, ...
                    struct('silentSec', adv.bootstrapSec));

                app.Metric1Value.Text = sprintf('%+.1f dB', m.noiseFloorDropDB);
                app.Metric2Value.Text = sprintf('%.2f s', numel(app.Original)/app.Fs);
                app.Metric3Value.Text = app.prettyAlgo(adv.algorithm);

                app.BtnPlayEnh.Enable = 'on';
                app.BtnSaveEnh.Enable = 'on';
                app.setStatus(sprintf( ...
                    'Done. Noise floor reduced by %+.1f dB. Compare with Play Original / Play Enhanced.', ...
                    m.noiseFloorDropDB));
            catch ME
                app.setStatus(sprintf('Processing error: %s', ME.message));
            end
        end

        function onPlayOriginal(app)
            app.stopPlayers();
            app.PlayerOrig = audioplayer(app.normalize(app.Original), app.Fs);
            play(app.PlayerOrig);
        end
        function onPlayEnhanced(app)
            app.stopPlayers();
            app.PlayerEnh = audioplayer(app.normalize(app.Enhanced), app.Fs);
            play(app.PlayerEnh);
        end
        function onSave(app)
            [f, p] = uiputfile({'*.wav'}, 'Save enhanced audio', 'enhanced.wav');
            figure(app.UIFigure);
            if isequal(f, 0), return; end
            audiowrite(fullfile(p, f), app.normalize(app.Enhanced), app.Fs);
            app.setStatus(sprintf('Saved: %s', fullfile(p, f)));
        end
    end

    % =====================================================================
    %  Callbacks - LMS tab
    % =====================================================================
    methods (Access = private)
        function onLmsRun(app)
            fs = app.Fs;
            durSec = 4.0;
            N = round(fs*durSec);
            t = (0:N-1)'/fs;

            clean = app.syntheticSpeech(fs, durSec);
            clean = clean / (max(abs(clean)) + 1e-9) * 0.8;

            rng(11);
            ref = 0.6*randn(N,1) + 0.2*sin(2*pi*250*t);
            [b, a] = butter(4, 1500/(fs/2));
            ref = filter(b, a, ref);

            hRoom = fir1(48, 0.4) .* exp(-(0:48)'/25);
            hRoom = hRoom / norm(hRoom);
            noisePrim = filter(hRoom, 1, ref);

            snrdB = app.SldLmsSNR.Value;
            sigPow = mean(clean.^2) + 1e-12;
            noisePow = mean(noisePrim.^2) + 1e-12;
            scale = sqrt(sigPow/noisePow) * 10^(-snrdB/20);
            noisePrim = scale * noisePrim; ref = scale * ref;
            primary = clean + noisePrim;

            filterLen = round(app.SldLmsLen.Value);
            mu = app.SldLmsMu.Value;
            [~, e, ~, mseTrace] = dsp.lmsCancel(primary, ref, filterLen, mu);

            app.LmsPrimary = primary; app.LmsError = e; app.LmsClean = clean;

            snrIn  = 10*log10(mean(clean.^2)/mean((primary-clean).^2 + 1e-12));
            snrOut = 10*log10(mean(clean.^2)/mean((e(1:numel(clean))-clean).^2 + 1e-12));

            tt = (0:numel(primary)-1)/fs;
            plot(app.AxLmsPrimary, tt, primary, 'Color', app.CLR_DANGER, 'LineWidth', 0.8);
            ylim(app.AxLmsPrimary, [-1 1]); grid(app.AxLmsPrimary, 'on');

            plot(app.AxLmsError, tt, e, 'Color', app.CLR_ACCENT, 'LineWidth', 0.8);
            ylim(app.AxLmsError, [-1 1]); grid(app.AxLmsError, 'on');

            plot(app.AxLmsMse, tt, 10*log10(mseTrace + 1e-12), ...
                'Color', app.CLR_PRIMARY, 'LineWidth', 1.4);
            grid(app.AxLmsMse, 'on');

            app.BtnLmsPlayIn.Enable = 'on'; app.BtnLmsPlayOut.Enable = 'on';
            app.LblLmsStatus.Text = sprintf( ...
                'Done. Filter %d taps, mu = %.3f. SNR: %.1f dB -> %.1f dB   (%+.1f dB)', ...
                filterLen, mu, snrIn, snrOut, snrOut-snrIn);
        end

        function onLmsPlayIn(app)
            app.stopLmsPlayers();
            app.LmsPlayerIn = audioplayer(app.normalize(app.LmsPrimary), app.Fs);
            play(app.LmsPlayerIn);
        end
        function onLmsPlayOut(app)
            app.stopLmsPlayers();
            app.LmsPlayerOut = audioplayer(app.normalize(app.LmsError), app.Fs);
            play(app.LmsPlayerOut);
        end
        function updateLmsLabels(app)
            app.LblLmsSNR.Text = sprintf('Input SNR: %+.0f dB', app.SldLmsSNR.Value);
            app.LblLmsMu.Text  = sprintf('Step size mu: %.3f', app.SldLmsMu.Value);
            app.LblLmsLen.Text = sprintf('Filter length: %d taps', round(app.SldLmsLen.Value));
        end
    end

    % =====================================================================
    %  Helpers
    % =====================================================================
    methods (Access = private)
        function setStatus(app, msg)
            app.LblStatus.Text = msg;
        end

        function s = prettyAlgo(~, key)
            switch key
                case 'wiener',  s = 'Wiener (DD + SPP)';
                case 'specsub', s = 'Spectral Subtraction';
                otherwise,      s = key;
            end
        end

        function y = normalize(~, x)
            p = max(abs(x));
            if p > 0, y = 0.98 * x / p; else, y = x; end
        end

        function stopPlayers(app)
            for p = {app.PlayerOrig, app.PlayerEnh}
                if ~isempty(p{1}) && isvalid(p{1}) && isplaying(p{1})
                    stop(p{1});
                end
            end
        end
        function stopLmsPlayers(app)
            for p = {app.LmsPlayerIn, app.LmsPlayerOut}
                if ~isempty(p{1}) && isvalid(p{1}) && isplaying(p{1})
                    stop(p{1});
                end
            end
        end

        function plotWave(app, ax, x, fs, ttl)
            t = (0:numel(x)-1)/fs;
            plot(ax, t, x, 'Color', app.CLR_PRIMARY, 'LineWidth', 0.7);
            xlim(ax, [0 max(t)+eps]); ylim(ax, [-1 1]);
            app.styleAxes(ax, ttl, 'time (s)', '');
        end

        function plotSpec(app, ax, x, fs, ttl)
            frameLen = 2*round(0.032*fs/2);
            hop = frameLen/2;
            win = hann(frameLen, 'periodic');
            [S, prm] = dsp.stftAnalyze(x(:), frameLen, hop, win);
            mag = 20*log10(abs(S) + 1e-6);
            f = (0:size(S,1)-1) * fs / prm.nfft;
            t = (0:size(S,2)-1) * hop / fs;
            imagesc(ax, t, f, mag); axis(ax, 'xy');
            ylim(ax, [0 fs/2]);
            colormap(ax, app.CLR_SPEC);
            top = max(mag(:));
            try, clim(ax, [top-60, top]); catch, caxis(ax, [top-60, top]); end
            app.styleAxes(ax, ttl, 'time (s)', 'Hz');
        end

        function startLevelTimer(app)
            app.stopLevelTimer();
            app.LevelTimer = timer('ExecutionMode', 'fixedRate', 'Period', 0.1, ...
                'TimerFcn', @(~,~) app.tickLevel());
            start(app.LevelTimer);
        end
        function stopLevelTimer(app)
            if ~isempty(app.LevelTimer) && isvalid(app.LevelTimer)
                try, stop(app.LevelTimer); catch, end
                delete(app.LevelTimer);
            end
            app.LevelTimer = [];
        end
        function tickLevel(app)
            if isempty(app.Recorder) || ~isvalid(app.Recorder) || ~isrecording(app.Recorder)
                app.LblLevel.Text = 'Mic level:  idle'; return;
            end
            try
                x = getaudiodata(app.Recorder, 'double');
                if numel(x) < 100, return; end
                tail = x(max(1,end-round(0.1*app.Fs)):end);
                dB = 20*log10(sqrt(mean(tail.^2)) + 1e-6);
                nBars = max(0, min(20, round((dB+60)/2)));
                bars = [repmat(char(9608), 1, nBars), repmat(char(9617), 1, 20-nBars)];
                app.LblLevel.Text = sprintf('Mic level: %s  %5.1f dBFS', bars, dB);
            catch
                app.LblLevel.Text = 'Mic level:  idle';
            end
        end

        function x = syntheticSpeech(~, fs, durSec)
            N = round(fs*durSec); t = (0:N-1)'/fs;
            f0 = 120 + 8*sin(2*pi*4.5*t);
            phase = 2*pi*cumsum(f0)/fs;
            x = zeros(N,1);
            for k = 1:20, x = x + (1/k)*sin(k*phase); end
            F1 = 500 + 200*sin(2*pi*0.7*t);
            F2 = 1500 + 400*sin(2*pi*0.5*t + 1);
            F3 = 2500 + 300*sin(2*pi*0.3*t + 2);
            x = fmt(x, F1, 80, fs); x = fmt(x, F2, 100, fs); x = fmt(x, F3, 120, fs);
            x(round(0.25*N):round(0.30*N)) = 0;
            x(round(0.62*N):round(0.68*N)) = 0;
            x = x / (max(abs(x)) + 1e-9);
            function y = fmt(x, Ft, BW, fs)
                y = zeros(size(x)); zi = [0;0];
                for n = 1:numel(x)
                    r = exp(-pi*BW/fs); th = 2*pi*Ft(n)/fs;
                    a1 = -2*r*cos(th); a2 = r*r;
                    y(n) = x(n) - a1*zi(1) - a2*zi(2);
                    zi = [y(n); zi(1)];
                end
            end
        end
    end
end

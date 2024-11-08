function [H, H_time] = nrPerfectChannelEstimate_custom(varargin)
%nrPerfectChannelEstimate perfect channel estimation
%   H = nrPerfectChannelEstimate(...) performs perfect channel estimation,
%   producing a perfect channel estimate H, by reconstructing the channel
%   impulse response from information about the propagation channel and
%   then performing OFDM demodulation. H is a K-by-N-by-Nr-by-Nt array
%   where K is the number of subcarriers, N is the number of OFDM symbols,
%   Nr is the number of receive antennas and Nt is the number of transmit
%   antennas.
%
%   H = nrPerfectChannelEstimate(CARRIER,PATHGAINS,PATHFILTERS)
%   performs perfect channel estimation by reconstructing the channel
%   impulse response from the channel path gains array PATHGAINS and path
%   filter impulse response matrix PATHFILTERS, and then performing OFDM
%   demodulation according to the carrier configuration given by CARRIER.
%
%   CARRIER is a carrier configuration object, <a 
%   href="matlab:help('nrCarrierConfig')"
%   >nrCarrierConfig</a>. Only these
%   object properties are relevant for this function:
%
%   SubcarrierSpacing - Subcarrier spacing in kHz (15, 30, 60, 120, 240, 480, 960)
%   CyclicPrefix      - Cyclic prefix ('normal', 'extended')
%   NSizeGrid         - Number of resource blocks in carrier resource grid
%                       (1...275)
%   NSlot             - Slot number
%
%   PATHGAINS must be an array of size Ncs-by-Np-by-Nt-by-Nr, where Ncs is
%   the number of channel snapshots and Np is the number of paths. The
%   times of the channel snapshots are given by the SAMPLETIMES input (see
%   below).
%
%   PATHFILTERS must be a matrix of size Nh-by-Np where Nh is the number of
%   impulse response samples.
%
%   H = nrPerfectChannelEstimate(PATHGAINS,PATHFILTERS,NRB,SCS,INITIALNSLOT)
%   perform perfect channel estimation as above, except in place of the
%   CARRIER configuration object the OFDM demodulation is performed using
%   NRB resource blocks (1...275) with subcarrier spacing SCS (15, 30, 60,
%   120, 240, 480, 960) and initial slot number INITIALNSLOT, a non-negative
%   scalar integer. The initial slot number is used modulo the number of 
%   slots per subframe to select the appropriate cyclic prefix lengths for
%   OFDM demodulation.
%
%   H = nrPerfectChannelEstimate(...,OFFSET) specifies the timing offset
%   OFFSET, an integer number of samples indicating where the OFDM
%   demodulation will start on the reconstructed waveform. The default is
%   to use <a href="matlab:doc('nrPerfectTimingEstimate')
%   ">nrPerfectTimingEstimate</a> to establish the timing offset.
%
%   H = nrPerfectChannelEstimate(...,OFFSET,SAMPLETIMES) specifies the
%   sample times SAMPLETIMES of the channel snapshots. SAMPLETIMES must be
%   of size Ncs-by-1 and specifies the time of occurrence of each channel
%   snapshot (the 1st dimension of PATHGAINS). The default is a vector of
%   times starting at zero, where the number of snapshots is given by the
%   1st dimension sizing of PATHGAINS and the sampling rate is equal to the
%   sampling rate used for OFDM modulation for the configured number of
%   resource blocks and subcarrier spacing. Ensure that the channel
%   snapshots span at least one slot. The function performs channel
%   estimation for each complete slot.
%
%   H = nrPerfectChannelEstimate(PATHGAINS,PATHFILTERS,...,CP) specifies
%   the cyclic prefix length. CP must be 'normal' for normal cyclic prefix
%   length (default) or 'extended' for extended cyclic prefix length.
%
%   H = nrPerfectChannelEstimate(...,NAME,VALUE) specifies additional
%   options as NAME,VALUE pairs to allow control over the OFDM demodulation
%   of the channel impulse responses:
%
%   CyclicPrefix         - Cyclic prefix ('normal' (default), 'extended').
%                          This option is only applicable for function
%                          syntaxes not using nrCarrierConfig
%   Nfft                 - Desired number of FFT points to use in the OFDM
%                          demodulator. If absent or set to [], a default 
%                          value is selected based on other parameters, see
%                          <a href="matlab: doc('nrOFDMDemodulate')"
%                          >nrOFDMDemodulate</a> for details
%   SampleRate           - Sample rate of the channel impulse responses. If 
%                          absent or set to [], the default value is 
%                          SampleRate = Nfft * SCS. If required, the
%                          channel impulse responses are resampled from the
%                          specified sample rate to the sample rate used
%                          during OFDM demodulation, Nfft * SCS
%   CyclicPrefixFraction - Starting position of OFDM symbol demodulation
%                          (FFT window position) within the cyclic prefix.
%                          Specified as a fraction of the cyclic prefix, in
%                          the range [0,1], with 0 representing the start
%                          of the cyclic prefix and 1 representing the end
%                          of the cyclic prefix. Default is 0.5
%
%   Note that for the numerologies specified in TS 38.211 Section 4.2, 
%   extended cyclic prefix length is only applicable for 60 kHz subcarrier
%   spacing.
%
%   % Example:
%   % Plot the estimated channel magnitude responses for two different 
%   % channel configurations.
%
%   % Configure a TDL-C channel with 100 ns delay spread and plot the 
%   % estimated channel magnitude response for the first receive antenna.
%
%   NRB = 25;
%   SCS = 60;
%   carrier = nrCarrierConfig;
%   carrier.NSizeGrid = NRB;
%   carrier.SubcarrierSpacing = SCS;
%   ofdmInfo = nrOFDMInfo(NRB,SCS);
%   
%   tdl = nrTDLChannel;
%   tdl.DelayProfile = 'TDL-C';
%   tdl.DelaySpread = 100e-9;
%   tdl.MaximumDopplerShift = 300;
%   tdl.SampleRate = ofdmInfo.SampleRate;
%   
%   T = tdl.SampleRate * 1e-3;
%   tdlInfo = info(tdl);
%   Nt = tdlInfo.NumTransmitAntennas;
%   in = complex(randn(T,Nt),randn(T,Nt));
%
%   [~,pathGains] = tdl(in);
%   pathFilters = getPathFilters(tdl);
%
%   hest = nrPerfectChannelEstimate(carrier,pathGains,pathFilters);
%   size(hest)
%
%   figure;
%   surf(abs(hest(:,:,1)));
%   shading('flat');
%   xlabel('OFDM symbols');
%   ylabel('Subcarriers');
%   zlabel('|H|');
%   title('Channel magnitude response');
%
%   % Repeat the channel estimate for extended cyclic prefix.
%
%   carrier.CyclicPrefix = 'Extended';
%   hest = nrPerfectChannelEstimate(carrier,pathGains,pathFilters);
%   size(hest)
%
%   % Configure a CDL-D channel with 30 ns delay spread and plot the 
%   % estimated channel magnitude response for the first receive antenna.
%   
%   cdl = nrCDLChannel;
%   cdl.DelayProfile = 'CDL-D';
%   cdl.DelaySpread = 30e-9;
%   cdl.MaximumDopplerShift = 5;
%   cdl.SampleRate = ofdmInfo.SampleRate;
%
%   cdlInfo = info(cdl);
%   Nt = cdlInfo.NumTransmitAntennas;
%   in = complex(randn(T,Nt),randn(T,Nt));
%
%   [~,pathGains,sampleTimes] = cdl(in);
%   pathFilters = getPathFilters(cdl);
%
%   offset = nrPerfectTimingEstimate(pathGains,pathFilters);
%
%   hest = nrPerfectChannelEstimate(carrier,pathGains,pathFilters,...
%              offset,sampleTimes);
%
%   figure;
%   surf(abs(hest(:,:,1)));
%   shading('flat');
%   xlabel('OFDM symbols');
%   ylabel('Subcarriers');
%   zlabel('|H|');
%   title('Channel magnitude response');
%
%   See also nrPerfectTimingEstimate, nrChannelEstimate, nrTimingEstimate,
%   nrTDLChannel, nrCDLChannel, nrCarrierConfig.

%   Copyright 2018-2023 The MathWorks, Inc.

%#codegen

    narginchk(3,17);
    
    % Parse and validate optional inputs or inputs whose position depends
    % upon the syntax, and calculate OFDM information structure 'ofdminfo'
    [pathGains,pathFilters,offset,sampleTimes, ...
        ofdminfo,sampleTimesDefaulted,initialNSlot,hasSampleRate, ...
        OFDM_span, considerCP, return_timeDomain] = ...
        getOptionalInputs(varargin{:});
    
    % Get number of channel impulse response samples 'Nh'
    Nh = size(pathFilters,1);
    
    % Get number of channel snapshots 'Ncs', number of transmit antennas
    % 'Nt' and number of receive antennas 'Nr' in the path gains array
    [Ncs,~,Nt,Nr] = size(pathGains);

    % Return an empty channel estimate if Ncs = 0 (no channel snapshots)
    K = ofdminfo.NSubcarriers;
    if (Ncs==0)
        N = 0;
        H = zeros([K N Nr Nt],'like',pathGains);
        return;
    end
    
    % Set the origin of the sample times to zero, and establish the range
    % of possible durations 'T_min'...'T_max' corresponding to the sample
    % times
    sampleTimes = sampleTimes - sampleTimes(1);
    T_cg = mean(diff(sampleTimes));
    if (Ncs > 1)
        % The calculations here determine the range of 'T' in 
        % wireless.internal.channelmodels.CDLChannel/getSampleTimes for
        % which Ncs channel snapshots could have been produced, in the case
        % that SampleDensity~=Inf
        D_min = (Ncs - 1.5 + eps(Ncs)) * T_cg;
        T_min = ceil(D_min * ofdminfo.SampleRate);
        D_max = (Ncs - 0.5) * T_cg;
        T_max = floor(D_max * ofdminfo.SampleRate);
        % If 'T_min' and 'T_max' are equal, (1 / T_cg) and
        % ofdminfo.SampleRate are effectively equal, therefore the sample
        % times have one snapshot per input sample i.e. T = Ncs
        if (T_min==T_max)
            T_min = Ncs;
            T_max = Ncs;
        end
    else
        T_min = 1;
        T_max = 1;
    end
    
    % Establish the total number of subframes spanned by 'T_max', rounded
    % up, which determines the required number of repetitions of the cyclic
    % prefix lengths, and calculate the corresponding number of slots
    % 'nSlots'
    samplesPerSubframe = ofdminfo.SampleRate * 1e-3;
    nSlots = ceil(T_max / samplesPerSubframe) * ofdminfo.SlotsPerSubframe;
    
    % Establish the starting and ending sample indices of each OFDM symbol
    % across the total number of subframes, taking into consideration the
    % initial slot number, and update the cyclic prefix lengths to span all
    % subframes
    cpLengths = nr5g.internal.OFDMInfoRelativeNSlot(ofdminfo,initialNSlot,nSlots * ofdminfo.SymbolsPerSlot);
    fftLengths = [0 repmat(ofdminfo.Nfft,1,numel(cpLengths)-1)];
    symbolStarts = cumsum(cpLengths + fftLengths);
    symbolEnds = symbolStarts + ofdminfo.Nfft;
    
    % Adjust the symbol start and end times if resampling is required
    % during OFDM demodulation
    r = ofdminfo.Resampling;
    if (any([r.L r.M]~=1))
        symbolStarts = symbolStarts * r.L / r.M;
        symbolEnds = symbolEnds * r.L / r.M;
    end
    
    % If the default value was used for 'sampleTimes', validate that the 
    % channel snapshots in 'pathGains' span at least one slot, or have 
    % only 1 snapshot
    if (sampleTimesDefaulted)
        samplesPerSlot = symbolEnds(ofdminfo.SymbolsPerSlot);
        if (size(pathGains,1) > 1)
            coder.internal.errorIf(size(pathGains,1) < samplesPerSlot, ...
                'nr5g:nrPerfectChannelEstimate:TooFewPathGains', ...
                size(pathGains,1),sprintf('%g',samplesPerSlot));
        end
    end
    
    % Ensure that total duration is at least one slot
    if numel(varargin)>5
        T_min = max(T_min,symbolEnds(OFDM_span));
        T_max = max(T_max,symbolEnds(OFDM_span));
    end
    
    % Establish how many OFDM symbols 'N' are spanned by 'T_min'...'T_max'
    % time samples and round down to nearest whole slot
    N = find(symbolStarts<=T_min & symbolEnds<=T_max,1,'last');
    N = N(1);
    N = N - mod(N,ofdminfo.SymbolsPerSlot);

    symbolStarts = symbolStarts(1:N);
    T = ceil(symbolEnds(N));
    
    % Adjust the channel coefficient sample time points 'sampleTimes' to 
    % give updated time points 't' which minimize the error when choosing
    % elements of 'pathGains'. This is achieved by adjusting the timeline
    % by half of the sample period in 'sampleTimes':
    %
    %  using 'sampleTimes'                  using 't'
    % ---------------------          ---------------------
    %
    % *** |                          *** 
    %    *0*-----------              ---*0*-----
    %       ***       |                    *** |
    %          ***    |       --->            ***
    %             *** |                        | ***
    %                *0*---                    -----*0*---
    %                   ***                            ***
    %
    % * represents the channel coefficients at the input sampling rate 
    %   (from which samples 'pathGains' were taken during the channel 
    %   modeling process)
    % 0 represents channel coefficient samples in 'pathGains', calculated
    %   at 'sampleTimes'
    % - represents zero order hold of 'pathGains' to the input sampling 
    %   rate
    % Note that if 'sampleTimes' is scalar, no adjustment is made
    if (Ncs > 1)
        t = [0; sampleTimes + T_cg/2];
    else
        t = sampleTimes;
    end
    
    % Establish which OFDM symbol start times correspond to which channel
    % coefficient sample times 't'. 'idx' is a vector of length 'N'
    % indicating the 1st dimension index of 'pathGains' for each OFDM
    % symbol start time.
    symbolStartTimes = (symbolStarts + offset) / ofdminfo.SampleRate;
    idx = sum(symbolStartTimes>=t,1);
    if (any(idx>size(pathGains,1)))
        coder.internal.error( ...
            'nr5g:nrPerfectChannelEstimate:TooFewSnapshots', ...
            floor(t(end)*ofdminfo.SampleRate), ...
            sprintf('%g',symbolStarts(end)+offset));
    end
    
    % Prepare the path gains matrix by indexing using 'idx' to select a
    % first dimension element for each OFDM symbol start, and permute to
    % put the multipath components in the first dimension and switch the
    % antenna dimensions. The pathGains are now of size Np-by-Nr-by-Nt-by-N
    pathGains = pathGains(idx,:,:,:);
    pathGains = permute(pathGains,[2 4 3 1]);

    % Create channel impulse response array 'h' for each impulse response
    % sample, receive antenna, transmit antenna and OFDM symbol. For each
    % path, add its contribution to the channel impulse response across all
    % transmit antennas, receive antennas and OFDM symbols
    h = pagemtimes(pathFilters,pathGains);
    
    % Adjust gain of 'h' to account for resampling required during OFDM
    % demodulation
    h = h * r.L / r.M;

    % Create the empty received waveform (for each transmit antenna)
    rxWave = zeros([T Nr Nt],'like',pathGains);
    
    % For each OFDM symbol, add the corresponding impulse response samples
    % across all transmit antennas and receive antennas to the received
    % waveform. Note that the impulse responses are positioned according to
    % the timing offset 'offset' and the channel filter delay so that
    % channel estimate produced is as similar as possible to that produced
    % for a filtered waveform (without incurring the time cost of the full
    % filtering)
    tl = fix(symbolStarts) - offset + (1:Nh).';
    h = reshape(permute(h,[1 4 2 3]),[],Nr,Nt);
    rxWave(tl,:,:) = h;

    % For each transmit antenna, OFDM demodulate the received waveform
    % across all receive antennas to form the overall channel estimate
    % array
    rxWave = reshape(rxWave,[],Nr*Nt);
    H_time = rxWave;
    H = nr5g.internal.OFDMDemodulate(rxWave,ofdminfo,initialNSlot,N,hasSampleRate);
    H = reshape(H,K,N,Nr,Nt);    

    % For each OFDM symbol, adjust the channel estimate phase to account
    % for any fractional delay in the symbol start times due to resampling
    if (any([r.L r.M]~=1))
        k = (-K/2:K/2 - 1).' / ofdminfo.Nfft * r.M / r.L;
        phi = -2 * pi * mod(symbolStarts,1) .* k;
        H = H .* exp(1i*phi);
    end
    
end

function [pathGains,pathFilters,offset,sampleTimes,ofdminfo,sampleTimesDefaulted,initialNSlot,hasSampleRate, OFDM_span, considerCP, return_timeDomain] = getOptionalInputs(varargin)
    
    if numel(varargin)>5
        OFDM_span = varargin{6};
        considerCP = varargin{7};
        return_timeDomain = varargin{8};
    else 
        OFDM_span = 14; 
        considerCP = false;
        return_timeDomain = false;
    end

    fcnName = 'nrPerfectChannelEstimate';

    persistent defaultopts;

    if (isempty(defaultopts))

        defaultopts = nr5g.internal.parseOptions(fcnName,{'CyclicPrefix','Nfft','SampleRate','CyclicPrefixFraction'});

    end
    
    % Determine if syntax with nrCarrierConfig is being used and parse
    % relevant inputs
    isCarrierSyntax = isa(varargin{1},'nrCarrierConfig');
    if (isCarrierSyntax) % CARRIER,PATHGAINS,PATHFILTERS,...
        carrier = varargin{1};
        validateattributes(carrier,{'nrCarrierConfig'}, ...
            {'scalar'},fcnName,'Carrier specific configuration object');
        pathGains = varargin{2};
        pathFilters = varargin{3};
        initialNSlot = carrier.NSlot;
        optstart = 4;
    else % PATHGAINS,PATHFILTERS,NRB,SCS,INITIALNSLOT,...
        narginchk(5,17);
        pathGains = varargin{1};
        pathFilters = varargin{2};
        NRB = varargin{3};
        SCS = varargin{4};
        initialNSlot = varargin{5};
        optstart = 6;
    end
    
    % Validate channel path gains
    validateattributes(pathGains,{'double','single'}, ...
        {},fcnName,'PATHGAINS');
    coder.internal.errorIf(ndims(pathGains)>4, ...
        'nr5g:nrPerfectChannelEstimate:InvalidPathDims',ndims(pathGains));
    
    % Validate path filters impulse response
    validateattributes(pathFilters,{'double'}, ...
        {'2d'},fcnName,'PATHFILTERS');
    coder.internal.errorIf(size(pathGains,2)~=size(pathFilters,2), ...
        'nr5g:nrPerfectChannelEstimate:InconsistentPaths', ...
        size(pathGains,2),size(pathFilters,2));
    
    if (~isCarrierSyntax)
        % Validate the number of resource blocks (1...275)
        validateattributes(NRB,{'numeric'}, ...
            {'real','integer','scalar','>=',1,'<=',275},fcnName,'NRB');

        % Validate subcarrier spacing input in kHz (15/30/60/120/240/480/960)
        validateattributes(SCS,{'numeric'}, ...
            {'real','integer','scalar'},fcnName,'SCS');
        validSCS = [15 30 60 120 240 480 960];
        if (~any(SCS==validSCS))
            coder.internal.error(...
                'nr5g:nrPerfectChannelEstimate:InvalidSCS', ...
                SCS,num2str(validSCS));
        end

        % Validate zero-based initial slot number
        validateattributes(initialNSlot,{'numeric'}, ...
            {'real','nonnegative','scalar','integer'}, ...
            fcnName,'INITIALNSLOT');
    end
    
    % Parse optional arguments: 'offset', 'sampleTimes', and options.
    % Options are either name-value pairs, or a char/string value for the
    % cyclic prefix length. These options can appear in any position among
    % the 'offset' and 'sampleTimes' arguments, but multiple name-value
    % pairs must appear together. The value-only cyclic prefix length is
    % only valid for syntaxes without nrCarrierConfig
    argpos = [0 0]; % positions of offset and sampleTimes, 0 if absent
    pos = 1;
    firstoptarg = 0; % position of first option, 0 if absent
    cpnamefn = @(x)any(strcmpi(x,{'normal','extended'}));
    for i = optstart:5
        if (ischar(varargin{i}) || isstring(varargin{i}) ...
                || isstruct(varargin{i}) || pos>2)
            if (firstoptarg==0)
                firstoptarg = i;
            end
        else
            if (firstoptarg==0 || cpnamefn(varargin{firstoptarg}) ...
                    || isstruct(varargin{firstoptarg}) || ...
                    (mod(i,2) == mod(firstoptarg,2)))
                argpos(pos) = i;
                pos = pos + 1;
            end
        end
    end
    
    if (firstoptarg~=0)
        lastoptarg = min([argpos(argpos~=0 & argpos>firstoptarg)-1 nargin]);
    end
    
    % Parse options and get OFDM information
    if (isCarrierSyntax)
        optNames = {'Nfft','SampleRate','CyclicPrefixFraction'};
        if firstoptarg~=0
            opts = nr5g.internal.parseOptions(fcnName,optNames,varargin{firstoptarg:lastoptarg});
        else
            optins = {};
            opts = nr5g.internal.parseOptions(fcnName,optNames,optins{:});
        end
        
        % If performing code generation, the presence of sample rate with the
        % function syntax using nrCarrierConfig triggers a compile-time error
        hasSampleRate = ~isempty(opts.SampleRate);
        coder.internal.errorIf(~coder.target('MATLAB') && hasSampleRate, ...
            'nr5g:nrPerfectChannelEstimate:CompilationCarrierSampleRate');

        ofdminfo = nr5g.internal.OFDMInfo(carrier,opts);
    else
        optNames = {'CyclicPrefix','Nfft','SampleRate','CyclicPrefixFraction'};
        if firstoptarg~=0
            if (numel(varargin)>firstoptarg && ~cpnamefn(varargin{firstoptarg}))
                opts = nr5g.internal.parseOptions(fcnName,optNames,varargin{firstoptarg:lastoptarg});
                ECP = strcmpi(opts.CyclicPrefix,'extended');                
            else
                coder.internal.errorIf(lastoptarg~=firstoptarg, ...
                    'nr5g:nrPerfectChannelEstimate:CPValueOnlyOption');
                cp = varargin{firstoptarg};
                validateattributes(cp,{'char' 'string'},{},fcnName,'CP');
                cp = validatestring(cp,{'normal','extended'},fcnName,'CP');
                ECP = strcmpi(cp,'extended');
                opts = defaultopts;
            end
            ofdminfo = nr5g.internal.OFDMInfo(NRB,SCS,ECP,opts);
        else
            opts = defaultopts;
            ofdminfo = nr5g.internal.OFDMInfo(NRB,SCS,0,opts);
        end

        % If performing code generation and 'SampleRate' is supplied, then
        % NRB, SCS, Nfft, and SampleRate must be constant at compile time.
        hasSampleRate = ~isempty(opts.SampleRate);
        coder.internal.errorIf(~coder.target('MATLAB') && hasSampleRate && ...
            (~coder.internal.isConst(NRB) || ~coder.internal.isConst(SCS) || ...
            ~coder.internal.isConst(opts.Nfft) || ~coder.internal.isConst(opts.SampleRate)), ...
            'nr5g:nrPerfectChannelEstimate:NonConstantNfftScsSampleRateNrb');
    end
    
    % Validate offset or provide a default value
    if argpos(1)~=0
        offset = varargin{argpos(1)};
        Nh = size(pathFilters,1);
        validateattributes(offset,{'numeric'}, ...
            {'real','nonnegative','scalar'},fcnName,'offset');
        coder.internal.errorIf(offset>(Nh-1), ...
            'nr5g:nrPerfectChannelEstimate:InvalidOffset', ...
            offset,Nh);
    else
        % Default: use nrPerfectTimingEstimate to establish the timing
        % offset
        offset = nrPerfectTimingEstimate(pathGains,pathFilters);
    end

    % Adjust offset and path filters to remove any part of the channel that
    % occurs before the start of the cyclic prefix
    mincplen = min(ofdminfo.CyclicPrefixLengths);
    rem = max(0,offset - mincplen);
    offset = offset - rem;
    pathFilters = pathFilters(1+rem:end,:);

    % Adjust path filters to remove any part of the channel that occurs
    % after the end of the nominal OFDM symbol length
    pathFilters = pathFilters(1:min(end,ofdminfo.Nfft),:);
    
    % Validate sampleTimes or provide a default value
    if argpos(2)~=0
        sampleTimes = varargin{argpos(2)};
        Ncs = size(pathGains,1);
        validateattributes(sampleTimes,{'double'}, ...
            {'column','increasing'},fcnName,'sampleTimes');
        coder.internal.errorIf(length(sampleTimes)~=Ncs, ...
            'nr5g:nrPerfectChannelEstimate:InvalidSampleTimes', ...
            length(sampleTimes),Ncs);
        sampleTimesDefaulted = false;
    else
        % Default: vector of times at the OFDM sampling rate, one for each
        % channel snapshot in 'pathGains' and starting at zero
        sampleTimes = (0:(size(pathGains,1)-1)).' / ofdminfo.SampleRate;
        sampleTimesDefaulted = true;
    end
    
end

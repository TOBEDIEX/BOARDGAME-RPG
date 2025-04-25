--[[
    Advanced Animation Framework for Roblox
    
    Features:
    - Modular architecture
    - Animation state machine
    - Animation blending and transitions
    - Priority-based animation system
    - Event-driven architecture
    - Performance optimizations
    - Support for animation groups
    - Automated loading and caching
]]

local AnimationFramework = {}
AnimationFramework.__index = AnimationFramework

-- Constants
local ANIMATION_STATES = {
    STOPPED = "Stopped",
    PLAYING = "Playing",
    PAUSED = "Paused",
    QUEUED = "Queued",
    BLENDING = "Blending"
}

local PRIORITY_LEVELS = {
    IDLE = 1,
    MOVEMENT = 2,
    ACTION = 3,
    CORE = 4,
    OVERRIDE = 5
}

local DEFAULT_FADE_TIME = 0.3
local DEFAULT_WEIGHT = 1
local DEFAULT_SPEED = 1
local ANIMATION_CACHE_TIMEOUT = 60 -- seconds

-- Private variables and utility functions
local function deepCopy(original)
    local copy = {}
    for k, v in pairs(original) do
        if type(v) == "table" then
            copy[k] = deepCopy(v)
        else
            copy[k] = v
        end
    end
    return copy
end

local function createSignal()
    local connections = {}
    
    local function connect(fn)
        table.insert(connections, fn)
        
        local connection = {
            Disconnect = function()
                for i, conn in ipairs(connections) do
                    if conn == fn then
                        table.remove(connections, i)
                        break
                    end
                end
            end
        }
        
        return connection
    end
    
    local function fire(...)
        for _, fn in ipairs(connections) do
            coroutine.wrap(function(...)
                fn(...)
            end)(...)
        end
    end
    
    return {
        Connect = connect,
        Fire = fire
    }
end

-- Core animation manager class
function AnimationFramework.new(character)
    local self = setmetatable({}, AnimationFramework)
    
    -- Core properties
    self.Character = character
    self.Humanoid = character:FindFirstChildOfClass("Humanoid")
    self.Animator = self.Humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator", self.Humanoid)
    
    -- Animation storage
    self.AnimationObjects = {} -- {[id] = AnimationObject}
    self.LoadedAnimations = {} -- {[id] = AnimationTrack}
    self.PlayingAnimations = {} -- {[id] = {track = AnimationTrack, priority = number, weight = number}}
    self.AnimationGroups = {} -- {[groupName] = {animIds = {}, exclusive = bool}}
    self.AnimationCache = {} -- {[id] = {lastUsed = time, track = AnimationTrack}}
    
    -- Animation state tracking
    self.CurrentAnimations = {} -- Currently playing animations by bodyPart
    self.AnimationQueue = {} -- Queued animations
    self.TransitioningAnimations = {} -- Animations in transition
    
    -- Events
    self.Events = {
        AnimationPlayed = createSignal(),
        AnimationStopped = createSignal(),
        AnimationLooped = createSignal(),
        AnimationTransitioned = createSignal(),
        AnimationError = createSignal()
    }
    
    -- Performance tracking
    self.PerformanceStats = {
        AnimationsPlayed = 0,
        AnimationsStopped = 0,
        AnimationsLoaded = 0,
        CacheHits = 0,
        CacheMisses = 0,
        BlendOperations = 0
    }
    
    -- Start cache cleanup task
    self:_startCacheCleanup()
    
    return self
end

-- Animation Loading and Preparation --

function AnimationFramework:LoadAnimation(id, animationId, priority, options)
    -- Validate and set default parameters
    assert(type(id) == "string", "Animation ID must be a string")
    assert(type(animationId) == "string", "Roblox Animation ID must be a string")
    
    priority = priority or PRIORITY_LEVELS.MOVEMENT
    options = options or {}
    
    -- Create animation object if it doesn't already exist
    if not self.AnimationObjects[id] then
        local animation = Instance.new("Animation")
        animation.AnimationId = animationId
        
        self.AnimationObjects[id] = {
            Id = id,
            RobloxId = animationId,
            Animation = animation,
            Priority = priority,
            Options = deepCopy(options)
        }
        
        -- Load the animation track
        local success, track = pcall(function()
            return self.Animator:LoadAnimation(animation)
        end)
        
        if success and track then
            self.LoadedAnimations[id] = track
            self.PerformanceStats.AnimationsLoaded = self.PerformanceStats.AnimationsLoaded + 1
            
            -- Set up animation events
            track.Stopped:Connect(function()
                self:_handleAnimationStopped(id)
            end)
            
            track.DidLoop:Connect(function()
                self:_handleAnimationLooped(id)
            end)
            
            return track
        else
            self.Events.AnimationError:Fire("Failed to load animation: " .. id)
            return nil
        end
    else
        -- Return existing track
        return self.LoadedAnimations[id]
    end
end

function AnimationFramework:PreloadAnimations(animationData)
    for id, data in pairs(animationData) do
        self:LoadAnimation(id, data.animationId, data.priority, data.options)
    end
end

-- Animation Playback Control --

function AnimationFramework:PlayAnimation(id, fadeTime, weight, speed, options)
    -- Validate the animation exists or has been loaded
    if not self.AnimationObjects[id] then
        self.Events.AnimationError:Fire("Animation not found: " .. id)
        return nil
    end
    
    -- Use defaults or provided values
    fadeTime = fadeTime or DEFAULT_FADE_TIME
    weight = weight or DEFAULT_WEIGHT
    speed = speed or DEFAULT_SPEED
    options = options or {}
    
    local animObject = self.AnimationObjects[id]
    local track = self.LoadedAnimations[id]
    
    -- Handle animation priorities and transitions
    local canPlay = self:_checkPriorityAndTransition(id, animObject.Priority)
    
    if not canPlay then
        if options.queueIfBlocked then
            table.insert(self.AnimationQueue, {
                id = id,
                fadeTime = fadeTime,
                weight = weight,
                speed = speed,
                options = options
            })
            return nil
        else
            self.Events.AnimationError:Fire("Animation blocked by higher priority: " .. id)
            return nil
        end
    end
    
    -- Stop any conflicting animations in the same group if needed
    self:_handleAnimationGroups(id)
    
    -- Play the animation
    track:Play(fadeTime)
    track:AdjustWeight(weight)
    track:AdjustSpeed(speed)
    
    -- Record as currently playing
    self.PlayingAnimations[id] = {
        track = track,
        priority = animObject.Priority,
        weight = weight,
        speed = speed,
        startTime = os.time(),
        options = options
    }
    
    -- Update performance stats
    self.PerformanceStats.AnimationsPlayed = self.PerformanceStats.AnimationsPlayed + 1
    
    -- Fire played event
    self.Events.AnimationPlayed:Fire(id, track)
    
    -- Handle automatic stopping if duration is specified
    if options.duration then
        delay(options.duration, function()
            if self.PlayingAnimations[id] then
                self:StopAnimation(id, fadeTime)
            end
        end)
    end
    
    return track
end

function AnimationFramework:StopAnimation(id, fadeTime)
    fadeTime = fadeTime or DEFAULT_FADE_TIME
    
    local playingAnimation = self.PlayingAnimations[id]
    if not playingAnimation then
        return false
    end
    
    local track = playingAnimation.track
    track:Stop(fadeTime)
    
    -- Remove from playing animations
    self.PlayingAnimations[id] = nil
    
    -- Update cache
    self.AnimationCache[id] = {
        lastUsed = os.time(),
        track = track
    }
    
    -- Update performance stats
    self.PerformanceStats.AnimationsStopped = self.PerformanceStats.AnimationsStopped + 1
    
    -- Process queue
    self:_processAnimationQueue()
    
    return true
end

function AnimationFramework:StopAllAnimations(fadeTime)
    fadeTime = fadeTime or DEFAULT_FADE_TIME
    
    for id, _ in pairs(self.PlayingAnimations) do
        self:StopAnimation(id, fadeTime)
    end
end

function AnimationFramework:PauseAnimation(id)
    local playingAnimation = self.PlayingAnimations[id]
    if not playingAnimation then
        return false
    end
    
    playingAnimation.track:Pause()
    return true
end

function AnimationFramework:ResumeAnimation(id)
    local playingAnimation = self.PlayingAnimations[id]
    if not playingAnimation then
        return false
    end
    
    playingAnimation.track:Play()
    return true
end

-- Animation Modification --

function AnimationFramework:ChangeAnimationSpeed(id, speed)
    local playingAnimation = self.PlayingAnimations[id]
    if not playingAnimation then
        return false
    end
    
    playingAnimation.track:AdjustSpeed(speed)
    playingAnimation.speed = speed
    return true
end

function AnimationFramework:ChangeAnimationWeight(id, weight)
    local playingAnimation = self.PlayingAnimations[id]
    if not playingAnimation then
        return false
    end
    
    playingAnimation.track:AdjustWeight(weight)
    playingAnimation.weight = weight
    
    -- Update blending stats
    self.PerformanceStats.BlendOperations = self.PerformanceStats.BlendOperations + 1
    
    return true
end

-- Animation Groups --

function AnimationFramework:CreateAnimationGroup(groupName, animationIds, options)
    options = options or {}
    
    self.AnimationGroups[groupName] = {
        animIds = animationIds,
        exclusive = options.exclusive == nil and true or options.exclusive,
        priority = options.priority or PRIORITY_LEVELS.MOVEMENT
    }
end

function AnimationFramework:PlayAnimationGroup(groupName, fadeTime, weight, speed, options)
    local group = self.AnimationGroups[groupName]
    if not group then
        self.Events.AnimationError:Fire("Animation group not found: " .. groupName)
        return
    end
    
    -- If exclusive, stop any playing animations in this group
    if group.exclusive then
        for _, id in ipairs(group.animIds) do
            if self.PlayingAnimations[id] then
                self:StopAnimation(id, fadeTime)
            end
        end
    end
    
    -- Play each animation in the group
    local tracks = {}
    for _, id in ipairs(group.animIds) do
        local track = self:PlayAnimation(id, fadeTime, weight, speed, options)
        if track then
            table.insert(tracks, track)
        end
    end
    
    return tracks
end

function AnimationFramework:StopAnimationGroup(groupName, fadeTime)
    local group = self.AnimationGroups[groupName]
    if not group then
        return false
    end
    
    for _, id in ipairs(group.animIds) do
        self:StopAnimation(id, fadeTime)
    end
    
    return true
end

-- Advanced Blending and Transitions --

function AnimationFramework:BlendAnimations(fromId, toId, duration, curve)
    curve = curve or "Linear" -- Linear, Smooth, Sharp, etc.
    
    local fromAnim = self.PlayingAnimations[fromId]
    local toTrack = self.LoadedAnimations[toId]
    
    if not fromAnim or not toTrack then
        self.Events.AnimationError:Fire("Cannot blend: one or both animations not available")
        return false
    end
    
    -- Start blending process
    local fromTrack = fromAnim.track
    local startWeight = fromAnim.weight
    local startTime = os.time()
    local endTime = startTime + duration
    
    -- Play the target animation at zero weight
    toTrack:Play()
    toTrack:AdjustWeight(0)
    
    -- Register as transitioning
    self.TransitioningAnimations[fromId] = {
        toId = toId,
        progress = 0,
        startTime = startTime,
        endTime = endTime,
        curve = curve
    }
    
    -- Start blending coroutine
    coroutine.wrap(function()
        while os.time() < endTime and self.PlayingAnimations[fromId] and toTrack.IsPlaying do
            local elapsed = os.time() - startTime
            local progress = math.clamp(elapsed / duration, 0, 1)
            
            -- Apply easing based on curve
            local easedProgress
            if curve == "Smooth" then
                easedProgress = progress * progress * (3 - 2 * progress) -- Smooth step
            elseif curve == "Sharp" then
                easedProgress = progress * progress -- Quadratic
            else
                easedProgress = progress -- Linear
            end
            
            -- Update weights
            fromTrack:AdjustWeight(startWeight * (1 - easedProgress))
            toTrack:AdjustWeight(startWeight * easedProgress)
            
            -- Update transition progress
            if self.TransitioningAnimations[fromId] then
                self.TransitioningAnimations[fromId].progress = progress
            end
            
            -- Performance tracking
            self.PerformanceStats.BlendOperations = self.PerformanceStats.BlendOperations + 1
            
            wait(0.03) -- Small wait for performance
        end
        
        -- Finalize transition
        if self.PlayingAnimations[fromId] then
            self:StopAnimation(fromId, 0)
        end
        
        if toTrack.IsPlaying then
            toTrack:AdjustWeight(startWeight)
            self.PlayingAnimations[toId] = {
                track = toTrack,
                priority = self.AnimationObjects[toId].Priority,
                weight = startWeight,
                speed = fromAnim.speed,
                startTime = os.time()
            }
        end
        
        -- Clear transition data
        self.TransitioningAnimations[fromId] = nil
        
        -- Fire event
        self.Events.AnimationTransitioned:Fire(fromId, toId)
    end)()
    
    return true
end

function AnimationFramework:CrossFadeGroup(fromGroupName, toGroupName, duration)
    local fromGroup = self.AnimationGroups[fromGroupName]
    local toGroup = self.AnimationGroups[toGroupName]
    
    if not fromGroup or not toGroup then
        self.Events.AnimationError:Fire("Cannot crossfade: one or both groups not found")
        return false
    end
    
    -- Crossfade each animation in the groups
    for i, fromId in ipairs(fromGroup.animIds) do
        local toId = toGroup.animIds[i]
        if toId and self.PlayingAnimations[fromId] then
            self:BlendAnimations(fromId, toId, duration)
        end
    end
    
    return true
end

-- Event Handling --

function AnimationFramework:OnAnimationPlayed(callback)
    return self.Events.AnimationPlayed:Connect(callback)
end

function AnimationFramework:OnAnimationStopped(callback)
    return self.Events.AnimationStopped:Connect(callback)
end

function AnimationFramework:OnAnimationLooped(callback)
    return self.Events.AnimationLooped:Connect(callback)
end

function AnimationFramework:OnAnimationTransitioned(callback)
    return self.Events.AnimationTransitioned:Connect(callback)
end

function AnimationFramework:OnAnimationError(callback)
    return self.Events.AnimationError:Connect(callback)
end

-- Utility Methods --

function AnimationFramework:GetPlayingAnimations()
    local result = {}
    for id, data in pairs(self.PlayingAnimations) do
        table.insert(result, {
            id = id,
            priority = data.priority,
            weight = data.weight,
            speed = data.speed,
            playTime = os.time() - data.startTime
        })
    end
    return result
end

function AnimationFramework:IsAnimationPlaying(id)
    return self.PlayingAnimations[id] ~= nil
end

function AnimationFramework:GetPerformanceStats()
    return deepCopy(self.PerformanceStats)
end

-- Internal Helper Methods --

function AnimationFramework:_checkPriorityAndTransition(id, priority)
    -- Check if any higher priority animations would block this one
    for playingId, data in pairs(self.PlayingAnimations) do
        if data.priority > priority and self.AnimationObjects[playingId].Options.blockLowerPriority then
            return false
        end
    end
    
    return true
end

function AnimationFramework:_handleAnimationGroups(id)
    -- Find which groups this animation belongs to
    for groupName, group in pairs(self.AnimationGroups) do
        if table.find(group.animIds, id) and group.exclusive then
            -- Stop other animations in the same group
            for _, animId in ipairs(group.animIds) do
                if animId ~= id and self.PlayingAnimations[animId] then
                    self:StopAnimation(animId)
                end
            end
        end
    end
end

function AnimationFramework:_handleAnimationStopped(id)
    -- Fire event
    self.Events.AnimationStopped:Fire(id)
    
    -- Process queue
    self:_processAnimationQueue()
end

function AnimationFramework:_handleAnimationLooped(id)
    -- Fire event
    self.Events.AnimationLooped:Fire(id)
    
    -- Handle looping options
    local playingAnim = self.PlayingAnimations[id]
    if playingAnim and playingAnim.options.loopCount then
        playingAnim.loopCount = (playingAnim.loopCount or 1) + 1
        
        if playingAnim.loopCount >= playingAnim.options.loopCount then
            self:StopAnimation(id)
        end
    end
end

function AnimationFramework:_processAnimationQueue()
    if #self.AnimationQueue > 0 then
        local nextAnim = table.remove(self.AnimationQueue, 1)
        self:PlayAnimation(
            nextAnim.id,
            nextAnim.fadeTime,
            nextAnim.weight,
            nextAnim.speed,
            nextAnim.options
        )
    end
end

function AnimationFramework:_startCacheCleanup()
    -- Periodically clean up unused animations
    spawn(function()
        while true do
            wait(30) -- Check every 30 seconds
            
            local currentTime = os.time()
            for id, cacheData in pairs(self.AnimationCache) do
                if currentTime - cacheData.lastUsed > ANIMATION_CACHE_TIMEOUT and not self.PlayingAnimations[id] then
                    self.AnimationCache[id] = nil
                end
            end
        end
    end)
end

-- Animation State Machine --

function AnimationFramework:CreateStateMachine(states)
    local stateMachine = {
        states = states,
        currentState = nil,
        previousState = nil,
        transitions = {},
        onStateChanged = createSignal()
    }
    
    function stateMachine:AddTransition(fromState, toState, condition, options)
        options = options or {}
        
        if not self.transitions[fromState] then
            self.transitions[fromState] = {}
        end
        
        table.insert(self.transitions[fromState], {
            toState = toState,
            condition = condition,
            blendTime = options.blendTime or DEFAULT_FADE_TIME,
            interruptible = options.interruptible == nil and true or options.interruptible
        })
    end
    
    function stateMachine:SetState(stateName)
        if not self.states[stateName] then
            return false
        end
        
        local oldState = self.currentState
        self.previousState = oldState
        self.currentState = stateName
        
        -- Stop current animations if needed
        if oldState and self.states[oldState].animations then
            for _, animId in ipairs(self.states[oldState].animations) do
                AnimationFramework:StopAnimation(animId)
            end
        end
        
        -- Play new state animations
        if self.states[stateName].animations then
            for _, animId in ipairs(self.states[stateName].animations) do
                AnimationFramework:PlayAnimation(animId)
            end
        end
        
        -- Fire state change event
        self.onStateChanged:Fire(oldState, stateName)
        
        return true
    end
    
    function stateMachine:Update(context)
        if not self.currentState then
            return
        end
        
        -- Check for valid transitions
        local transitions = self.transitions[self.currentState]
        if not transitions then
            return
        end
        
        for _, transition in ipairs(transitions) do
            if transition.condition(context) then
                self:SetState(transition.toState)
                break
            end
        end
    end
    
    function stateMachine:OnStateChanged(callback)
        return self.onStateChanged:Connect(callback)
    end
    
    return stateMachine
end

-- Return the module
return AnimationFramework

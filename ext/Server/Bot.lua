class('Bot');

require('__shared/Config');
require('Waypoint');

local Globals = require('Globals');

function Bot:__init(player)
	--Player Object
	self.player = player;
	self.name = player.name;
	self.id = player.id;

	--common settings
	self._spawnMode = 0;
	self._moveMode = 0;
	self.kit = "";
	self.color = "";
	self._checkSwapTeam = false;
	self._respawning = false;

	--timers
	self._updateTimer = 0;
	self._aimUpdateTimer = 0;
	self._spawnDelayTimer = 0;
	self._wayWaitTimer = 0;
	self._obstaceSequenceTimer = 0;
	self._shotTimer = 0;
	self._shootModeTimer = nil;
	self._attackModeMoveTimer = 0;
	self._meleeCooldownTimer = 0;
	self._shootTraceTimer = 0;

	--shared movement vars
	self.activeMoveMode = 0;
	self.activeSpeedValue = 0;

	--advanced movement
	self._currentWayPoint = nil;
	self._targetYaw = 0.0;
	self._pathIndex = 0;
	self._lastWayDistance = 0;
	self._nrOfIndexIncreases = 0;
	self._invertPathDirection = false;
	self._obstacleRetryCounter = 0;

	--shooting
	self._shoot = false;
	self._shootPlayer = nil;
	self._shootWayPoints = {};
	self._lastTargetTrans = Vec3();
	self._lastShootPlayer = nil;

	--simple movement
	self._botSpeed = 0;
	self._targetPlayer = nil;
	self._spawnTransform = LinearTransform();
end

function Bot:onUpdate(dt)
	if self.player.soldier ~= nil then
		self.player.soldier:SingleStepEntry(self.player.controlledEntryId);
	end

	self._updateTimer		= self._updateTimer + dt;
	self._aimUpdateTimer	= self._aimUpdateTimer + dt;

	if self._aimUpdateTimer > StaticConfig.botAimUpdateCycle then
		self:_updateAiming(dt);
		self._aimUpdateTimer = 0; --reset afterwards, to use it for targetinterpolation
	end

	self:_updateYaw();

	if self._updateTimer > StaticConfig.botUpdateCycle then
		self._updateTimer = 0;

		self:_setActiveVars();
		self:_updateRespwawn();
		self:_updateShooting();
		self:_updateMovement(); --TODO: move-mode shoot
	end
end


--public functions
function Bot:shootAt(player, ignoreYaw)
	local dYaw		= 0;
	local fovHalf	= 0;

	if not ignoreYaw then
		local oldYaw	= self.player.input.authoritativeAimingYaw;
		local dy		= player.soldier.worldTransform.trans.z - self.player.soldier.worldTransform.trans.z;
		local dx		= player.soldier.worldTransform.trans.x - self.player.soldier.worldTransform.trans.x;
		local yaw		= (math.atan(dy, dx) > math.pi / 2) and (math.atan(dy, dx) - math.pi / 2) or (math.atan(dy, dx) + 3 * math.pi / 2);

		dYaw			= math.abs(oldYaw-yaw);

		if dYaw > math.pi then
			dYaw =math.pi * 2 - dYaw;
		end

		fovHalf = Config.fovForShooting / 360 * math.pi;
	end

	if dYaw < fovHalf or ignoreYaw then
		if self._shoot then
			if self._shootModeTimer == nil or self._shootModeTimer > Config.botMinTimeShootAtPlayer then
				self._shootModeTimer	= 0;
				self._shootPlayer		= player;
				self._shotTimer			= 0;
			end
		else
			self._shootModeTimer = Config.botFireModeDuration;
		end
	end
end

function Bot:setVarsDefault()
	self._spawnMode		= 5;
	self._moveMode		= 5;
	self._botSpeed		= 3;
	self._pathIndex		= 1;
	self._respawning	= Globals.respawnWayBots;
	self._shoot			= Globals.attackWayBots;
end

function Bot:resetVars()
	self._spawnMode				= 0;
	self._moveMode				= 0;
	self._pathIndex				= 0;
	self._respawning			= false;
	self._shoot					= false;
	self._targetPlayer			= nil;
	self._shootPlayer			= nil;
	self._lastShootPlayer		= nil;
	self._invertPathDirection	= false;
	self._nrOfIndexIncreases	= 0;
	self._updateTimer			= 0;
	self._aimUpdateTimer		= 0; --timer sync

	self.player.input:SetLevel(EntryInputActionEnum.EIAZoom, 0);
	self.player.input:SetLevel(EntryInputActionEnum.EIAFire, 0);
	self.player.input:SetLevel(EntryInputActionEnum.EIAQuicktimeFastMelee, 0);
	self.player.input:SetLevel(EntryInputActionEnum.EIAMeleeAttack, 0);
	self.player.input:SetLevel(EntryInputActionEnum.EIAQuicktimeJumpClimb, 0);
	self.player.input:SetLevel(EntryInputActionEnum.EIAJump, 0);
	self.player.input:SetLevel(EntryInputActionEnum.EIAStrafe, 0.0);
	self.player.input:SetLevel(EntryInputActionEnum.EIAThrottle, 0);
	self.player.input:SetLevel(EntryInputActionEnum.EIASprint, 0);
end

function Bot:setVarsStatic(player)
	self._spawnMode		= 0;
	self._moveMode		= 0;
	self._pathIndex		= 0;
	self._respawning	= false;
	self._shoot			= false;
	self._targetPlayer	= player;
end

function Bot:setVarsSimpleMovement(player, spawnMode, transform)
	self._spawnMode		= spawnMode;
	self._moveMode		= 2;
	self._botSpeed		= 3;
	self._pathIndex		= 0;
	self._respawning	= false;
	self._shoot			= false;
	self._targetPlayer	= player;

	if transform ~= nil then
		self._spawnTransform = transform;
	end
end

function Bot:setVarsWay(player, useRandomWay, pathIndex, currentWayPoint, inverseDirection)
	if useRandomWay then
		self._spawnMode		= 5;
		self._targetPlayer	= nil;
		self._shoot			= Globals.attackWayBots;
		self._respawning	= Globals.respawnWayBots;
	else
		self._spawnMode		= 4;
		self._targetPlayer	= player;
		self._shoot			= false;
		self._respawning	= false;
	end

	self._botSpeed				= 3;
	self._moveMode				= 5;
	self._pathIndex				= pathIndex;
	self._currentWayPoint		= currentWayPoint;
	self._invertPathDirection	= inverseDirection;
end

function Bot:isStaticMovement()
	if self._moveMode == 0 or self._moveMode == 3 or self._moveMode == 4 then
		return true;
	else
		return false;
	end
end

function Bot:setMoveMode(moveMode)
	self._moveMode = moveMode;
end

function Bot:setRespawn(respawn)
	self._respawning = respawn;
end

function Bot:setShoot(shoot)
	self._shoot = shoot;
end

function Bot:setWayIndex(wayIndex)
	self._pathIndex = wayIndex;
end

function Bot:setCurrentWayPoint(wayPoint)
	self._currentWayPoint = wayPoint;
end

function Bot:setDirectionInversion(invertWayDirection)
	self._invertPathDirection = invertWayDirection;
end

function Bot:setSpeed(speed)
	self._botSpeed = speed;
end

function Bot:getSpawnMode()
	return self._spawnMode;
end

function Bot:getWayIndex()
	return self._pathIndex;
end

function Bot:getSpawnTransform()
	return self._spawnTransform;
end

function Bot:getTargetPlayer()
	return self._targetPlayer;
end

function Bot:resetSpawnVars()
	self._spawnDelayTimer		= 0;
	self._obstaceSequenceTimer	= 0;
	self._obstacleRetryCounter	= 0;
	self._lastWayDistance		= 1000;
	self._shootPlayer			= nil;
	self._lastShootPlayer		= nil;
	self._shootModeTimer		= nil;
	self._meleeCooldownTimer	= 0;
	self._shootTraceTimer		= 0;
	self._attackModeMoveTimer	= 0;
	self._shootWayPoints		= {};
end

function Bot:clearPlayer(player)
	if self._shootPlayer == player then
		self._shootPlayer = nil;
	end

	if self._targetPlayer == player then
		self._targetPlayer = nil;
	end

	if self._lastShootPlayer == player then
		self._lastShootPlayer = nil;
	end
end

function Bot:destroy()
	self:resetVars();
	self.player.input	= nil;

	PlayerManager:DeletePlayer(self.player);
	self.player			= nil;
end

-- private functions
function Bot:_updateRespwawn()
	if self._respawning and self.player.soldier == nil and self._spawnMode > 0 then
		-- wait for respawn-delay gone
		if self._spawnDelayTimer < Config.spawnDelayBots then
			self._spawnDelayTimer = self._spawnDelayTimer + StaticConfig.botUpdateCycle;
		else
			Events:DispatchLocal('Bot:RespawnBot', self.name);
		end
	end
end

function Bot:_updateAiming(dt)
	if self.player.alive and self._shoot then
		if self._shootPlayer ~= nil and self._shootPlayer.soldier ~= nil then

			--interpolate player movement
			local targetMovement = Vec3(0, 0, 0);

			if self._lastShootPlayer ~= nil and self._lastShootPlayer == self._shootPlayer then
				targetMovement			= self._shootPlayer.soldier.worldTransform.trans - self._lastTargetTrans --movement in one dt
				--calculate how long the distance is --> time to travel
				local distanceToPlayer	= self._shootPlayer.soldier.worldTransform.trans:Distance(self.player.soldier.worldTransform.trans);
				local timeToTravel		= (distanceToPlayer / StaticConfig.botBulletSpeed) + dt;
				local factorForMovement	= timeToTravel / self._aimUpdateTimer;
				targetMovement			= targetMovement * factorForMovement;
			end

			self._lastShootPlayer = self._shootPlayer;
			self._lastTargetTrans = self._shootPlayer.soldier.worldTransform.trans:Clone();

			--calculate yaw and pith
			local dz		= self._shootPlayer.soldier.worldTransform.trans.z + targetMovement.z - self.player.soldier.worldTransform.trans.z;
			local dx		= self._shootPlayer.soldier.worldTransform.trans.x + targetMovement.x - self.player.soldier.worldTransform.trans.x;
			local dy		= (self._shootPlayer.soldier.worldTransform.trans.y + targetMovement.y + self:_getCameraHight(self._shootPlayer.soldier, true)) - (self.player.soldier.worldTransform.trans.y + self:_getCameraHight(self.player.soldier, false));
			local atanDzDx	= math.atan(dz, dx);
			local yaw		= (atanDzDx > math.pi / 2) and (atanDzDx - math.pi / 2) or (atanDzDx + 3 * math.pi / 2);

			--calculate pitch
			local distance	= math.sqrt(dz ^ 2 + dx ^ 2);
			local pitch		= math.atan(dy, distance);

			self.player.input.authoritativeAimingPitch		= pitch;
			self._targetYaw									= yaw;
		end
	end
end

function Bot:_updateYaw()
	local otherDirection = false;
	local deltaYaw = self.player.input.authoritativeAimingYaw - self._targetYaw;
	local absDeltaYaw = math.abs(deltaYaw)
	if absDeltaYaw > math.pi then
		otherDirection = true;
		absDeltaYaw = math.abs(absDeltaYaw - 2*math.pi)
	end
	if absDeltaYaw < Globals.yawPerFrame then
		self.player.input.authoritativeAimingYaw = self._targetYaw;
		return;
	end

	local inkrement = Globals.yawPerFrame;
	if deltaYaw > 0 or (deltaYaw < 0 and otherDirection) then
		inkrement = -inkrement;
	end
	local tempYaw = self.player.input.authoritativeAimingYaw + inkrement;
	if tempYaw >= (math.pi * 2) then
		tempYaw = tempYaw - (math.pi * 2);
	elseif tempYaw < 0.0 then
		tempYaw = tempYaw + (math.pi * 2);
	end
	self.player.input.authoritativeAimingYaw = tempYaw
end

function Bot:_updateShooting()
	if self.player.alive and self._shoot then
		--select weapon-slot TODO: keep button pressed or not?
		if self._obstaceSequenceTimer == 0 and self._shootModeTimer == nil then
			if self.player.soldier.weaponsComponent ~= nil then
				if Config.botWeapon == "Knive" then
					if self.player.soldier.weaponsComponent.currentWeaponSlot ~= WeaponSlot.WeaponSlot_7 then
						self.player.input:SetLevel(EntryInputActionEnum.EIASelectWeapon7, 1);
						self.player.input:SetLevel(EntryInputActionEnum.EIASelectWeapon2, 0);
						self.player.input:SetLevel(EntryInputActionEnum.EIASelectWeapon1, 0);
					else
						self.player.input:SetLevel(EntryInputActionEnum.EIASelectWeapon7, 0);
					end
				elseif Config.botWeapon == "Pistol" then
					if self.player.soldier.weaponsComponent.currentWeaponSlot ~= WeaponSlot.WeaponSlot_1 then
						self.player.input:SetLevel(EntryInputActionEnum.EIASelectWeapon7, 0);
						self.player.input:SetLevel(EntryInputActionEnum.EIASelectWeapon2, 1);
						self.player.input:SetLevel(EntryInputActionEnum.EIASelectWeapon1, 0);
					else
						self.player.input:SetLevel(EntryInputActionEnum.EIASelectWeapon2, 0);
					end
				else --"Primary"
					if self.player.soldier.weaponsComponent.currentWeaponSlot ~= WeaponSlot.WeaponSlot_0 then
						self.player.input:SetLevel(EntryInputActionEnum.EIASelectWeapon7, 0);
						self.player.input:SetLevel(EntryInputActionEnum.EIASelectWeapon2, 0);
						self.player.input:SetLevel(EntryInputActionEnum.EIASelectWeapon1, 1);
					else
						self.player.input:SetLevel(EntryInputActionEnum.EIASelectWeapon1, 0);
					end
				end
			end
		end

		if self._shootPlayer ~= nil and self._shootPlayer.soldier ~= nil then
			if self._shootModeTimer < Config.botFireModeDuration then
				self._shootModeTimer	= self._shootModeTimer + StaticConfig.botUpdateCycle;
				self.activeMoveMode		= 9; -- movement-mode : attack
				--self.player.input:SetLevel(EntryInputActionEnum.EIAZoom, 1) --does not work.

				--check for melee attack
				if Config.meleeAttackIfClose and self._shootPlayer.soldier.worldTransform.trans:Distance(self.player.soldier.worldTransform.trans) < 1 then
					if self._meleeCooldownTimer <= 0 then
						--self.player.input:SetLevel(EntryInputActionEnum.EIAQuicktimeFastMelee, 1);
						self.player.input:SetLevel(EntryInputActionEnum.EIAMeleeAttack, 1);
						self._meleeCooldownTimer = Config.meleeAttackCoolDown;
						Events:DispatchLocal("ServerDamagePlayer", self._shootPlayer.name, self.player.name, true);
					else
						self._meleeCooldownTimer = self._meleeCooldownTimer - StaticConfig.botUpdateCycle;

						if self._meleeCooldownTimer < 0 then
							self._meleeCooldownTimer = 0;
						end

						--self.player.input:SetLevel(EntryInputActionEnum.EIAQuicktimeFastMelee, 0);
						self.player.input:SetLevel(EntryInputActionEnum.EIAMeleeAttack, 0);
					end
				else
					--self.player.input:SetLevel(EntryInputActionEnum.EIAQuicktimeFastMelee, 0);
					self.player.input:SetLevel(EntryInputActionEnum.EIAMeleeAttack, 0);
				end

				--trace way back
				if self._shootTraceTimer > StaticConfig.traceDeltaShooting then
					--create a Trace to find way back
					self._shootTraceTimer 	= 0;
					local point				= WayPoint();
					point.trans				= self.player.soldier.worldTransform.trans:Clone();
					point.speedMode			= 4;

					table.insert(self._shootWayPoints, point);
				end
				self._shootTraceTimer = self._shootTraceTimer + StaticConfig.botUpdateCycle;

				--shooting sequence
				if Config.botWeapon == "Knive" then
					self.player.input:SetLevel(EntryInputActionEnum.EIAFire, 0);
					self._shotTimer	= 0;
				elseif Config.botWeapon == "Pistol" then
					if self._shotTimer >= Config.botFireCyclePistol then
						self._shotTimer	= 0;
					end
					if self._shotTimer >= (Config.botFireCyclePistol / 2) then
						self.player.input:SetLevel(EntryInputActionEnum.EIAFire, 0);
					else
						self.player.input:SetLevel(EntryInputActionEnum.EIAFire, 1);
					end
				else --primary
					if self.player.soldier.pose ~= CharacterPoseType.CharacterPoseType_Crouch then -- wait till crouch
						self._shotTimer =  -Config.botFirstShotDelay;
					end
					if self.kit == "Support" then
						if self._shotTimer >= (Config.botFireDurationSupport + Config.botFirePauseSupport) then
							self._shotTimer	= 0;
						end
						if self._shotTimer >= Config.botFireDurationSupport then
							self.player.input:SetLevel(EntryInputActionEnum.EIAFire, 0);
						elseif self._shotTimer >= 0 then
							self.player.input:SetLevel(EntryInputActionEnum.EIAFire, 1);
						end
					elseif self.kit == "Recon" then
						if self._shotTimer >= Config.botFireCycleRecon then
							self._shotTimer	= 0;
						end
						if self._shotTimer >= (Config.botFireCycleRecon / 2) then
							self.player.input:SetLevel(EntryInputActionEnum.EIAFire, 0);
						elseif self._shotTimer >= 0 then
							self.player.input:SetLevel(EntryInputActionEnum.EIAFire, 1);
						end
					else -- Enineer and Assalut
						if self._shotTimer >= (Config.botFireDuration + Config.botFirePause) then
							self._shotTimer	= 0;
						end
						if self._shotTimer >= Config.botFireDuration then
							self.player.input:SetLevel(EntryInputActionEnum.EIAFire, 0);
						elseif self._shotTimer >= 0 then
							self.player.input:SetLevel(EntryInputActionEnum.EIAFire, 1);
						end
					end
				end

				self._shotTimer = self._shotTimer + StaticConfig.botUpdateCycle;

			else
				self.player.input:SetLevel(EntryInputActionEnum.EIAFire, 0);
				self._shootPlayer		= nil;
				self._lastShootPlayer	= nil;
			end
		else
			self.player.input:SetLevel(EntryInputActionEnum.EIAZoom, 0);
			self.player.input:SetLevel(EntryInputActionEnum.EIAFire, 0);
			self.player.input:SetLevel(EntryInputActionEnum.EIAQuicktimeFastMelee, 0);
			self.player.input:SetLevel(EntryInputActionEnum.EIAMeleeAttack, 0);
			self._shootPlayer		= nil;
			self._lastShootPlayer	= nil;
			self._shootModeTimer	= nil;
		end
	end
end


function Bot:_getNextWaypoint()
	local activePointIndex = 1;

	if self._currentWayPoint == nil then
		self._currentWayPoint = activePointIndex;
	else
		activePointIndex = self._currentWayPoint;

		-- direction handling
		if activePointIndex > #Globals.wayPoints[self._pathIndex] then
			if Globals.wayPoints[self._pathIndex][1].optValue == 0xFF then --inversion needed
				activePointIndex			= #Globals.wayPoints[self._pathIndex];
				self._invertPathDirection	= true;
			else
				activePointIndex			= 1;
			end
		elseif activePointIndex < 1 then
			if Globals.wayPoints[self._pathIndex][1].optValue == 0xFF then --inversion needed
				activePointIndex			= 1;
				self._invertPathDirection	= false;
			else
				activePointIndex			= #Globals.wayPoints[self._pathIndex];
			end
		end
	end
	return activePointIndex;
end

function Bot:_updateMovement()
	-- movement-mode of bots
	local additionalMovementPossible = true;

	if self.player.alive then
		-- pointing
		if self.activeMoveMode == 2 and self._targetPlayer ~= nil then
			if self._targetPlayer.soldier ~= nil then
				local dy		= self._targetPlayer.soldier.worldTransform.trans.z - self.player.soldier.worldTransform.trans.z;
				local dx		= self._targetPlayer.soldier.worldTransform.trans.x - self.player.soldier.worldTransform.trans.x;
				local atanDzDx	= math.atan(dy, dx);
				local yaw		= (atanDzDx > math.pi / 2) and (atanDzDx - math.pi / 2) or (atanDzDx + 3 * math.pi / 2);
				self._targetYaw = yaw;
			end

		-- mimicking
		elseif self.activeMoveMode == 3 and self._targetPlayer ~= nil then
			additionalMovementPossible = false;

			for i = 0, 36 do
				self.player.input:SetLevel(i, self._targetPlayer.input:GetLevel(i));
			end

			self._targetYaw								= self._targetPlayer.input.authoritativeAimingYaw;
			self.player.input.authoritativeAimingPitch	= self._targetPlayer.input.authoritativeAimingPitch;

		-- mirroring
		elseif self.activeMoveMode == 4 and self._targetPlayer ~= nil then
			additionalMovementPossible = false;

			for i = 0, 36 do
				self.player.input:SetLevel(i, self._targetPlayer.input:GetLevel(i));
			end

			self._targetYaw	= self._targetPlayer.input.authoritativeAimingYaw + ((self._targetPlayer.input.authoritativeAimingYaw > math.pi) and -math.pi or math.pi);
			self.player.input.authoritativeAimingPitch	= self._targetPlayer.input.authoritativeAimingPitch;

		-- move along points
		elseif self.activeMoveMode == 5 then

			-- get next point
			local activePointIndex = self:_getNextWaypoint();

			if Globals.wayPoints[self._pathIndex][1] ~= nil then -- check for reached point
				local point				= nil;
				local pointIncrement	= 1;
				local useShootWayPoint	= false;

				if #self._shootWayPoints > 0 then	--we need to go back to path first
					point				= table.remove(self._shootWayPoints);
					useShootWayPoint	= true;
				else
					point				= Globals.wayPoints[self._pathIndex][activePointIndex];
				end

				if (point.speedMode) > 0 then -- movement
					self._wayWaitTimer			= 0;
					self.activeSpeedValue		= point.speedMode; --speed
					

					--detect obstacle and move over or around
					local obstacleDetected = false;
					local currentWayPontDistance = self.player.soldier.worldTransform.trans:Distance(point.trans);
					if currentWayPontDistance >= self._lastWayDistance then
						if not useShootWayPoint then
							self._nrOfIndexIncreases = self._nrOfIndexIncreases + 1;
							activePointIndex = self:_getNextWaypoint();
							point = Globals.wayPoints[self._pathIndex][activePointIndex];
							if self._nrOfIndexIncreases > 3 then
								obstacleDetected = true;
							end
						else
							obstacleDetected = true;
						end
					end

					local dy					= point.trans.z - self.player.soldier.worldTransform.trans.z;
					local dx					= point.trans.x - self.player.soldier.worldTransform.trans.x;
					local distanceFromTarget	= math.sqrt(dx ^ 2 + dy ^ 2);
					local heightDistance		= math.abs(point.trans.y - self.player.soldier.worldTransform.trans.y);
					-- detect movement yaw
					local atanDzDx	= math.atan(dy, dx);
					local yaw		= (atanDzDx > math.pi / 2) and (atanDzDx - math.pi / 2) or (atanDzDx + 3 * math.pi / 2);
					self._targetYaw = yaw;

					if obstacleDetected or self._obstaceSequenceTimer ~= 0 then
						-- try to get around obstacle
						self.activeSpeedValue = 3; --always try to stand

						if self._obstaceSequenceTimer == 0 then --step 0
							self.player.input:SetLevel(EntryInputActionEnum.EIAJump, 0);
							self.player.input:SetLevel(EntryInputActionEnum.EIAQuicktimeJumpClimb, 0);

						elseif self._obstaceSequenceTimer > 2.0 then --step 4 - repeat afterwards
							self._obstaceSequenceTimer = 0;
							self._obstacleRetryCounter = self._obstacleRetryCounter + 1;
							self.player.input:SetLevel(EntryInputActionEnum.EIAMeleeAttack, 0);
							self.player.input:SetLevel(EntryInputActionEnum.EIAFire, 0.0);
						
						elseif self._obstaceSequenceTimer > 1.8 then --step 3
							self.player.input:SetLevel(EntryInputActionEnum.EIAStrafe, 0.0);
							if self._obstacleRetryCounter == 1 then
								self.player.input:SetLevel(EntryInputActionEnum.EIAFire, 1.0);
							else
								self.player.input:SetLevel(EntryInputActionEnum.EIAMeleeAttack, 1); --maybe a fence?
							end
							
						elseif self._obstaceSequenceTimer > 0.4 then --step 2
							self.player.input:SetLevel(EntryInputActionEnum.EIAJump, 0);
							self.player.input:SetLevel(EntryInputActionEnum.EIAQuicktimeJumpClimb, 0);
							self.player.input.authoritativeAimingPitch		= 0.0;
							if (MathUtils:GetRandomInt(0,1) == 1) then
								self.player.input:SetLevel(EntryInputActionEnum.EIAStrafe, 1.0);
							else
								self.player.input:SetLevel(EntryInputActionEnum.EIAStrafe, -1.0);
							end

						elseif self._obstaceSequenceTimer > 0.0 then --step 1
							self.player.input:SetLevel(EntryInputActionEnum.EIAQuicktimeJumpClimb, 1);
							self.player.input:SetLevel(EntryInputActionEnum.EIAJump, 1);
						end

						self._obstaceSequenceTimer = self._obstaceSequenceTimer + StaticConfig.botUpdateCycle;

						if self._obstacleRetryCounter >= 2 then --tried twice, try next waypoint
							self._obstacleRetryCounter	= 0;
							distanceFromTarget			= 0;
							heightDistance				= 0;
							pointIncrement				= 5; -- go 5 points further
						end
					else
						self._lastWayDistance = currentWayPontDistance;

						self.player.input:SetLevel(EntryInputActionEnum.EIAQuicktimeJumpClimb, 0);
						self.player.input:SetLevel(EntryInputActionEnum.EIAJump, 0);
						self.player.input:SetLevel(EntryInputActionEnum.EIAStrafe, 0.0);
						self.player.input:SetLevel(EntryInputActionEnum.EIAMeleeAttack, 0);
						self.player.input:SetLevel(EntryInputActionEnum.EIAFire, 0.0);
					end

					-- jump detection. Much more simple now, but works fine ;-)
					if self._obstaceSequenceTimer == 0 then
						if (point.trans.y - self.player.soldier.worldTransform.trans.y) > 0.3 and Config.jumpWhileMoving and not useShootWayPoint then
							--detect, if a jump was recorded or not
							local timeForwardBackwardJumpDetection = 1.8; -- 1.5 s ahead and back
							local jumpValid = false;
							for i = 1, math.floor(timeForwardBackwardJumpDetection/StaticConfig.traceDelta) do
								local pointBefore = Globals.wayPoints[self._pathIndex][activePointIndex - i];
								local pointAfter = Globals.wayPoints[self._pathIndex][activePointIndex + i];
								if (pointBefore ~= nil and pointBefore.extraMode == 1) or (pointAfter ~= nil and pointAfter.extraMode == 1) then
									jumpValid = true;
									break;
								end
							end
							if jumpValid then
								self.player.input:SetLevel(EntryInputActionEnum.EIAJump, 1);
								self.player.input:SetLevel(EntryInputActionEnum.EIAQuicktimeJumpClimb, 1);
							end

						else --only reset, if no obstacle-sequence active
							self.player.input:SetLevel(EntryInputActionEnum.EIAQuicktimeJumpClimb, 0);
							self.player.input:SetLevel(EntryInputActionEnum.EIAJump, 0);
						end
					end

					--check for reached target
					if distanceFromTarget < StaticConfig.targetDistanceWayPoint and heightDistance < StaticConfig.targetHeightDistanceWayPoint then
						-- target reached
						if not useShootWayPoint then
							if self._invertPathDirection then
								self._currentWayPoint = activePointIndex - pointIncrement;
							else
								self._currentWayPoint = activePointIndex + pointIncrement;
							end

						elseif pointIncrement > 1 then
							for i = 1, pointIncrement - 1 do --one already gets removed on start of wayfinding
								table.remove(self._shootWayPoints);
							end
						end
						self._obstaceSequenceTimer	= 0;
						self._nrOfIndexIncreases 	= 0;
						self._lastWayDistance		= 1000;
					end
				else -- wait mode
					self._wayWaitTimer		= self._wayWaitTimer + StaticConfig.botUpdateCycle;
					self.activeSpeedValue	= 0;

					-- TODO: Move yaw while waiting?
					if self._wayWaitTimer > point.optValue then
						self._wayWaitTimer		= 0;
						if self._invertPathDirection then
							self._currentWayPoint	= activePointIndex - 1;
						else
							self._currentWayPoint	= activePointIndex + 1;
						end
					end
				end
			end

		-- Shoot MoveMode
		elseif self.activeMoveMode == 9 then
			--crouch moving (only mode with modified gun)
			if Config.botWeapon == "Knive" then --Knive Only Mode
				self.activeSpeedValue = 4; --run towards player
			elseif Config.botWeapon == "Primary" then
				self.activeSpeedValue = 2;
			else
				self.activeSpeedValue = 3; --TODO: Test aiming in Mode 2
			end
			local targetTime = 5.0
			local targetCycles = math.floor(targetTime / StaticConfig.traceDeltaShooting);

			if #self._shootWayPoints > targetCycles and Config.jumpWhileShooting then
				local distanceDone = self._shootWayPoints[#self._shootWayPoints].trans:Distance(self._shootWayPoints[#self._shootWayPoints-targetCycles].trans);
				if distanceDone < 1.5 then --no movement was possible. Try to jump over obstacle
					self.activeSpeedValue = 3;
					self.player.input:SetLevel(EntryInputActionEnum.EIAJump, 1);
					self.player.input:SetLevel(EntryInputActionEnum.EIAQuicktimeJumpClimb, 1);
				else
					self.player.input:SetLevel(EntryInputActionEnum.EIAJump, 0);
					self.player.input:SetLevel(EntryInputActionEnum.EIAQuicktimeJumpClimb, 0);
				end
			else
				self.player.input:SetLevel(EntryInputActionEnum.EIAJump, 0);
				self.player.input:SetLevel(EntryInputActionEnum.EIAStrafe, 0.0);
			end

			-- do some sidwards movement from time to time
			if self._attackModeMoveTimer > 20 then
				self._attackModeMoveTimer = 0;
				self.player.input:SetLevel(EntryInputActionEnum.EIAStrafe, 0.0);
			elseif self._attackModeMoveTimer > 17 then
				self.player.input:SetLevel(EntryInputActionEnum.EIAStrafe, -1.0);
			elseif self._attackModeMoveTimer > 13 then
				self.player.input:SetLevel(EntryInputActionEnum.EIAStrafe, 0.0);
			elseif self._attackModeMoveTimer > 12 then
				self.player.input:SetLevel(EntryInputActionEnum.EIAStrafe, 1.0);
			elseif self._attackModeMoveTimer > 9 then
				self.player.input:SetLevel(EntryInputActionEnum.EIAStrafe, 0);
			elseif self._attackModeMoveTimer > 7 then
				self.player.input:SetLevel(EntryInputActionEnum.EIAStrafe, 1.0);
			end

			self._attackModeMoveTimer = self._attackModeMoveTimer + StaticConfig.botUpdateCycle;
		end

		-- additional movement
		if additionalMovementPossible then
			local speedVal = 0;

			if self.activeMoveMode > 0 then
				if self.activeSpeedValue == 1 then
					speedVal = 1.0;

					if self.player.soldier.pose ~= CharacterPoseType.CharacterPoseType_Prone then
						self.player.soldier:SetPose(CharacterPoseType.CharacterPoseType_Prone, true, true);
					end

				elseif self.activeSpeedValue == 2 then
					speedVal = 1.0;

					if self.player.soldier.pose ~= CharacterPoseType.CharacterPoseType_Crouch then
						self.player.soldier:SetPose(CharacterPoseType.CharacterPoseType_Crouch, true, true);
					end

				elseif self.activeSpeedValue >= 3 then
					speedVal = 1.0;

					if self.player.soldier.pose ~= CharacterPoseType.CharacterPoseType_Stand then
						self.player.soldier:SetPose(CharacterPoseType.CharacterPoseType_Stand, true, true);
					end
				end
			end

			-- movent speed
			if self.player.alive then
				self.player.input:SetLevel(EntryInputActionEnum.EIAThrottle, speedVal);

				if self.activeSpeedValue > 3 then
					self.player.input:SetLevel(EntryInputActionEnum.EIASprint, 1);
				else
					self.player.input:SetLevel(EntryInputActionEnum.EIASprint, 0);
				end
			end
		end
	end
end

function Bot:_setActiveVars()
	self.activeMoveMode		= self._moveMode;
	self.activeSpeedValue	= self._botSpeed;
end

function Bot:_getCameraHight(soldier, isTarget)
	local camereaHight = 0;

	if not isTarget then
		camereaHight = 1.6; --bot.soldier.pose == CharacterPoseType.CharacterPoseType_Stand

		if soldier.pose == CharacterPoseType.CharacterPoseType_Prone then
			camereaHight = 0.3;
		elseif soldier.pose == CharacterPoseType.CharacterPoseType_Crouch then
			camereaHight = 1.0;
		end
	else
		camereaHight = 1.3; --bot.soldier.pose == CharacterPoseType.CharacterPoseType_Stand - reduce by 0.3

		if soldier.pose == CharacterPoseType.CharacterPoseType_Prone then
			camereaHight = 0.3; -- don't reduce
		elseif soldier.pose == CharacterPoseType.CharacterPoseType_Crouch then
			camereaHight = 0.8; -- reduce by 0.2
		end
	end

	return camereaHight;
end

return Bot;
class('WeaponModification');

require('__shared/Config');

function WeaponModification:__init()
	self.m_alreadyLoaded	= false;
	self.m_WeaponInstances	= {};

	self.m_maxAngles		= {};
	self.m_minAngles		= {};
	self.m_incPerShot		= {};

	self.m_maxRecoilPitch	= {};
	self.m_recoilIncShot	= {};
	self.m_maxRecoilYaw		= {};
	self.m_recoilIncShotMin	= {};
	self.m_recoilIncShotMax	= {};
end

function WeaponModification:_resetAll()
	self.m_alreadyLoaded	= false;
	self.m_WeaponInstances	= {};

	self.m_maxAngles		= {};
	self.m_minAngles		= {};
	self.m_incPerShot		= {};

	self.m_maxRecoilPitch	= {};
	self.m_recoilIncShot	= {};
	self.m_maxRecoilYaw		= {};
	self.m_recoilIncShotMin	= {};
	self.m_recoilIncShotMax	= {};
end

function WeaponModification:OnPartitionLoaded(p_Partition)
	local s_Instances = p_Partition.instances;

	for _, s_Instance in pairs(s_Instances) do
		if s_Instance ~= nil and s_Instance.typeInfo.name == 'SoldierWeaponData' then
			local s_SoldierWeaponData = _G[s_Instance.typeInfo.name](s_Instance);

			if s_SoldierWeaponData.soldierWeaponBlueprint ~= nil then
				if self.m_alreadyLoaded then
					self:_resetAll();
				end

				table.insert(self.m_WeaponInstances, s_SoldierWeaponData);
			end
		end
	end
end

function WeaponModification:ModifyAllWeapons(botAimWorsening)
	print(#self.m_WeaponInstances .. ' loaded weapons to modify');

	for i, weaponInstance in pairs(self.m_WeaponInstances) do
		self:_ModifyWeapon(weaponInstance , i, botAimWorsening);
	end

	self.m_alreadyLoaded = true;
end

function WeaponModification:_ModifyWeapon(p_SoldierWeaponData, index, botAimWorsening)
	local s_SoldierWeaponData	= self:_MakeWritable(p_SoldierWeaponData);
	local s_WeaponFiringData	= self:_MakeWritable(s_SoldierWeaponData.weaponFiring);

	if s_WeaponFiringData.weaponSway == nil then
		return;
	end

	local s_GunSwayData = self:_MakeWritable(s_WeaponFiringData.weaponSway);
	-- From here on, you can modify everything in GunSwayData
	local s_Crouch		= GunSwayCrouchProneData(s_GunSwayData.crouch);

	if s_Crouch ~= nil then
		local s_CrouchNoZoom = GunSwayBaseMoveData(s_Crouch.noZoom);

		--HipFire - no zoom - crouching
		if s_CrouchNoZoom ~= nil then
			--Only modify movemode of bots
			local s_MovingValue = GunSwayDispersionData(s_CrouchNoZoom.moving);

			if s_MovingValue ~= nil then
				if self.m_maxAngles[index] == nil then
					self.m_minAngles[index] = s_MovingValue.minAngle;
					self.m_maxAngles[index] = s_MovingValue.maxAngle;
					self.m_incPerShot[index] = s_MovingValue.increasePerShot;
				end

				s_MovingValue.minAngle 			= self.m_minAngles[index] * botAimWorsening;
				s_MovingValue.maxAngle 			= self.m_maxAngles[index] * botAimWorsening;
				s_MovingValue.increasePerShot 	= self.m_incPerShot[index] * botAimWorsening;
				--decreasePerSecond 	float
			end

			local s_RecoilData = GunSwayRecoilData(s_CrouchNoZoom.recoil);

			if s_RecoilData ~= nil then
				if self.m_maxRecoilPitch[index] == nil then
					self.m_maxRecoilPitch[index] = s_RecoilData.recoilAmplitudeMax;
					self.m_recoilIncShot[index] = s_RecoilData.recoilAmplitudeIncPerShot;
					self.m_maxRecoilYaw[index] = s_RecoilData.horizontalRecoilAmplitudeMax;
					self.m_recoilIncShotMin[index] = s_RecoilData.horizontalRecoilAmplitudeIncPerShotMin;
					self.m_recoilIncShotMax[index] = s_RecoilData.horizontalRecoilAmplitudeIncPerShotMax;
				end

				s_RecoilData.recoilAmplitudeMax 			= self.m_maxRecoilPitch[index] * botAimWorsening;
				s_RecoilData.recoilAmplitudeIncPerShot		= self.m_recoilIncShot[index] * botAimWorsening;
				s_RecoilData.horizontalRecoilAmplitudeMax 	= self.m_maxRecoilYaw[index] * botAimWorsening;
				s_RecoilData.horizontalRecoilAmplitudeIncPerShotMin = self.m_recoilIncShotMin[index] * botAimWorsening;
				s_RecoilData.horizontalRecoilAmplitudeIncPerShotMax = self.m_recoilIncShotMax[index] * botAimWorsening;
				-- recoilAmplitudeDecreaseFactor 	float
			end
		end
	end
end

function WeaponModification:_MakeWritable(p_Instance)
	if p_Instance == nil then
		return;
	end

	local s_Instance = _G[p_Instance.typeInfo.name](p_Instance);

	if p_Instance.isLazyLoaded == true then
		print('The instance ' .. tostring(p_Instance.instanceGuid) .. ' was modified, even though its lazyloaded');
		return;
	end

	if p_Instance.isReadOnly == nil then
		-- If .isReadOnly is nil it means that its not a DataContainer, it's a Structure. We return it casted
		print('The instance ' .. p_Instance.typeInfo.name .. ' is not a DataContainer, it\'s a Structure');
		return s_Instance;
	end

	if not p_Instance.isReadOnly then
		return s_Instance;
	end

	s_Instance:MakeWritable();

	return s_Instance;
end


return WeaponModification();
local Point3 = _radiant.csg.Point3
local TrainingDummyComponent = class()

function TrainingDummyComponent:initialize()
   self._json = radiant.entities.get_json(self) or {}
   self._allowed_jobs = self._json.allowed_jobs or {}

	self._sv.enabled = true
   self._sv.disable_health_percentage = self._json.disable_health_percentage or 0.3
   
   local limit_data = radiant.entities.get_entity_data(self._entity, 'stonehearth:item_placement_limit')
   self._dummy_type = limit_data and limit_data.tag
	self.__saved_variables:mark_changed()
end

function TrainingDummyComponent:create()
	self._is_create = true
end

function TrainingDummyComponent:activate()
   self._sv.combat_time = stonehearth.calendar:realtime_to_game_seconds(self._json.combat_time or 5)
   self._health_listener = radiant.events.listen(self._entity, 'stonehearth:expendable_resource_changed:health', self, self._on_health_changed)
   
   if self._dummy_type then
      self._parent_trace = self._entity:get_component('mob'):trace_parent('siege weapon added or removed')
         :on_changed(function(parent_entity)
            if not parent_entity then
               local entity_forms_component = self._entity:get_component('stonehearth:entity_forms')
               if entity_forms_component and not entity_forms_component:is_being_placed() then
                  -- Unregister this object if it was undeployed
                  self:_register_with_town(false)
               end
            else
               -- Register this object if it is placed
               self:_register_with_town(true)
            end
         end)
   end
end

function TrainingDummyComponent:destroy()
   if self._dummy_type then
      self:_register_with_town(false)
   end
   self:_destroy_listeners()
	self:_destroy_combat_timer()
end

function TrainingDummyComponent:_destroy_listeners()
   if self._health_listener then
		self._health_listener:destroy()
		self._health_listener = nil
   end
   if self._parent_trace then
		self._parent_trace:destroy()
		self._parent_trace = nil
	end
end

function TrainingDummyComponent:_destroy_combat_timer()
	if self._sv._combat_timer then
		self._sv._combat_timer:destroy()
		self._sv._combat_timer = nil
	end
end

function TrainingDummyComponent:_register_with_town(register)
   local player_id = radiant.entities.get_player_id(self._entity)
   local town = stonehearth.town:get_town(player_id)
   if town then
      if register then
         town:register_limited_placement_item(self._entity, self._dummy_type)
      else
         town:unregister_limited_placement_item(self._entity, self._dummy_type)
      end
   end
end

function TrainingDummyComponent:can_train_entity(uri)
   return uri and self._allowed_jobs[uri]
end

function TrainingDummyComponent:get_enabled()
	return self._sv.enabled
end

function TrainingDummyComponent:_disable()
	self._sv.enabled = false
	self:_destroy_combat_timer()
	self:_reset_combat_state()
	self.__saved_variables:mark_changed()
end

function TrainingDummyComponent:_enable()
	self._sv.enabled = true
	self.__saved_variables:mark_changed()
end

function TrainingDummyComponent:set_in_combat()
	self._entity:add_component('stonehearth:combat_state'):set_primary_target(self._entity)
	self:_refresh_combat_timer()
end

function TrainingDummyComponent:_refresh_combat_timer()
	self._sv._entered_combat_time = stonehearth.calendar:get_elapsed_time()
	if not self._sv._combat_timer then
		self:_create_combat_timer(self._sv.combat_time)
	end
end

function TrainingDummyComponent:_on_combat_timer()
	self:_destroy_combat_timer()

	-- check if we've been out of combat for long enough
	local current_time = stonehearth.calendar:get_elapsed_time()
	local ooc_time = (self._sv._entered_combat_time or 0) + self._sv.combat_time
	if ooc_time <= current_time then
		self:_reset_combat_state()
	else
		self:_create_combat_timer(ooc_time - current_time)
	end
end

function TrainingDummyComponent:_reset_combat_state()
	self._entity:add_component('stonehearth:combat_state'):set_primary_target(nil)
end

function TrainingDummyComponent:_create_combat_timer(ooc_time)
	self._sv._combat_timer = stonehearth.calendar:set_timer('training dummy combat', ooc_time, function() self:_on_combat_timer() end)
end

function TrainingDummyComponent:_on_health_changed(e)
	local percentage = radiant.entities.get_health_percentage(self._entity)

	if percentage >= 1 then
      self:_enable()
	elseif percentage < self._sv.disable_health_percentage then
      local town = stonehearth.town:get_town(self._entity)
      if town and town:is_entity_type_registered('stonehearth_ace:can_repair') then
         self:_disable()
      end
	end
end

return TrainingDummyComponent
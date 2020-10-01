local reference_tracker = {}
reference_tracker.__index = reference_tracker

function reference_tracker:new()
    local instance = {
      refs = {},
      ref_counts = {},
      deleted_refs = {},
    }
    setmetatable(instance, reference_tracker)
    return instance
end

function reference_tracker:has(ref_id)
  return self.refs[ref_id] ~= nil
end

function reference_tracker:get(ref_id)
  return self.refs[ref_id]
end

function reference_tracker:set(ref_id, ref, increment_count)
  self.refs[ref_id] = ref

  if increment_count == nil or increment_count == true then
    self.ref_counts[ref_id] = (self.ref_counts[ref_id] or 0) + 1
  end
end

function reference_tracker:remove(ref_id)
  self.ref_counts[ref_id] = self.ref_counts[ref_id] - 1;

  local added_to_deleted_refs = (self.deleted_refs[ref_id] == nil)
  self.deleted_refs[ref_id] = true

  return added_to_deleted_refs
end

function reference_tracker:count()
  -- count refs
  local count = 0
  for _, _ in pairs(self.refs) do
    count = count + 1
  end
  return count
end

function reference_tracker:garbage_collection()
  local deleted_refs = {}

  for ref_id, _ in pairs(self.deleted_refs) do
    table.insert(deleted_refs, ref_id)
  end

  for _, ref_id in ipairs(deleted_refs) do
    if self.ref_counts[ref_id] <= 0 then
      local ref = self:get(ref_id)

      --
      -- Ensure child schema instances have their references removed as well.
      --
      if ref._schema ~= nil then
        for field, field_type in pairs(ref._schema) do
          if (
            type(field_type) ~= "string" and
            ref[field] ~= nil and
            ref[field].__refid ~= nil and
            self:remove(ref[field].__refid)
          ) then
            table.insert(deleted_refs, ref[field].__refid)
          end
        end

      elseif ref._child_type['new'] ~= nil then
        ref:each(function(value)
          if self:remove(value.__refid) then
            table.insert(deleted_refs, value.__refid)
          end
        end)
      end

      self.refs[ref_id] = nil
      self.ref_counts[ref_id] = nil
    end
  end

  -- clear deleted refs
  self.deleted_refs = {}
end

function reference_tracker:clear()
  self.refs = {};
  self.ref_counts = {};
  self.deleted_refs = {};
end

return reference_tracker

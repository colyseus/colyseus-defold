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
  table.insert(self.deleted_refs, ref_id);
  self.ref_counts[ref_id] = self.ref_counts[ref_id] - 1;
end

function reference_tracker:garbage_collection()
  -- TODO: iterate through `deleted_refs`
end

function reference_tracker:clear()
  self.refs = {};
  self.ref_counts = {};
  self.deleted_refs = {};
end

return reference_tracker

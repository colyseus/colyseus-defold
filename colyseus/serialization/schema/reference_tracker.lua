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

function reference_tracker:add(refId, ref)
  self.refs[refId] = ref
  self.ref_counts[refId] = (self.ref_counts[refId] or 0) + 1
end

function reference_tracker:remove(refId, ref)
  table.insert(self.deleted_refs, ref);
  self.ref_counts[refId] = self.ref_counts[refId] - 1;
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

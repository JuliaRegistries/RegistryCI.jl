function _canonicalize_period(p::Dates.CompoundPeriod)
    return Dates.canonicalize(p)
end

function _canonicalize_period(p::Dates.Period)
    return _canonicalize_period(Dates.CompoundPeriod(p))
end

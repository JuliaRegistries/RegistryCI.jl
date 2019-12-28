struct NewPackage end
struct NewVersion end

struct AutoMergeCronJobError <: Exception
    msg::String
end

struct AutoMergeGuidelinesNotMet <: Exception
    msg::String
end

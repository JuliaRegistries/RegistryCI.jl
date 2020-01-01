struct NewPackage end
struct NewVersion end

abstract type AutoMergeException <: Exception
end

struct AutoMergeCronJobError <: AutoMergeException
    msg::String
end

struct AutoMergeGuidelinesNotMet <: AutoMergeException
    msg::String
end

struct AutoMergeAuthorNotAuthorized <: AutoMergeException
    msg::String
end

struct AutoMergePullRequestNotOpen <: AutoMergeException
    msg::String
end

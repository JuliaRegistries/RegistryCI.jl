package _Self.buildTypes

import jetbrains.buildServer.configs.kotlin.v2019_2.*
import jetbrains.buildServer.configs.kotlin.v2019_2.buildFeatures.PullRequests
import jetbrains.buildServer.configs.kotlin.v2019_2.buildFeatures.pullRequests

object Test : BuildType({
    // following parts are only stubs, to make them work, incorporate them into your CI settings
    params {
        param("env.vcsroot_branch", "%vcsroot.branch%")
        param("env.teamcity_pullRequest_title", "%teamcity.pullRequest.title%")
        param("env.teamcity_pullRequest_source_branch", "%teamcity.pullRequest.source.branch%")
        param("env.teamcity_pullRequest_number", "%teamcity.pullRequest.number%")
        param("teamcity.git.fetchAllHeads", "true")
    }

    features {
        pullRequests {
            provider = github {
                filterAuthorRole = PullRequests.GitHubRoleFilter.EVERYBODY
            }
        }
    }

})

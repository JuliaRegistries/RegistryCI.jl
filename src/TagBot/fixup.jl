const FIXUP_PR_TITLE = "TagBot: Use issue comment triggers"
const FIXUP_COMMIT_MESSAGE = "[ci skip] $FIXUP_PR_TITLE"
const FIXUP_PR_BODY = """
As requested, I've updated your TagBot configuration to use issue comment triggers.

Please note that this PR does not take into account your existing configuration.
If you had any custom configuration, you'll need to add it back yourself.
"""

const TAGBOT_YML = raw"""
name: TagBot
on:
  issue_comment:
    types:
      - created
  workflow_dispatch:
jobs:
  TagBot:
    if: github.event_name == 'workflow_dispatch' || github.actor == 'JuliaTagBot'
    runs-on: ubuntu-latest
    steps:
      - uses: JuliaRegistries/TagBot@v1
        with:
          token: ${{ secrets.GITHUB_TOKEN }}
          ssh: ${{ secrets.DOCUMENTER_KEY }}
"""

function should_open_fixup_pr(repo, issue)
    return fixup_comment_exists(repo, issue) &&
        !fixup_done(repo) &&
        tagbot_file(repo; issue_comments=true) === nothing
end

function get_fork(repo)
    fork = GH.create_fork(r; auth=AUTH[])
    # Make sure the fork is new, otherwise it might be outdated.
    if now(UTC) - fork.created_at > Minute(1)
        delete_repo(fork; auth=AUTH[])
        get_fork(r)
    end
end

function open_fixup_pr(repo)
    fork = get_fork(repo)
    head = GH.commit(fork, "HEAD"; auth=AUTH[])
    branch = "tagbot/$(randstring())"
    GH.create_reference(fork; auth=AUTH[], params=(;
        sha=head.sha,
        ref="refs/heads/$branch",
    ))
    path, contents = tagbot_file(fork)
    GH.update_file(fork, path; auth=AUTH[], params=(;
        branch=branch,
        content=base64encode(TAGBOT_YML),
        message=FIXUP_COMMIT_MESSAGE,
        sha=bytes2hex(sha1("blob $(length(current_yml))\0$contents")),
    ))
    return GH.create_pull_request(repo; auth=AUTH[], params=(;
        title=FIXUP_PR_TITLE,
        body=FIXUP_PR_BODY,
        head="$(TAGBOT_USER[]):$branch",
        base=fork.default_branch,
    ))
end

function fixup_comment_exists(repo, issue)
    kwargs = Dict(:auth => AUTH[], :page_limit => 1, :params => (; per_page=100))
    while true
        comments, pages = GH.comments(repo, issue; kwargs...)
        for comment in comments
            if is_fixup_trigger(comment)
                return true
            end
        end
        if haskey(pages, "next")
            delete!(kwargs, :params)
            kwargs[:start_page] = pages["next"]
        else
            return false
        end
    end
end

function is_fixup_trigger(comment)
    return c.user.login != TABGOT_USER[] && occursin(r"TagBot fix"i, c.body)
end

function fixup_done(repo)
    pulls, _ = GH.pull_requests(repo; auth=AUTH[], params=(;
        creator=TAGBOT_USER[],
        state="all",
    ))
    for pull in pulls
        if pull.title == FIXUP_PR_TITLE
            return true
        end
    end
    return false
end

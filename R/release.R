#' Create a new release on GitHub
#'
#' This must be done **before** a CRAN release.
#' @param bump The bump increment, either "dev", "patch", "minor" or "major".
#' @details
#' - bump description.
#' - update default config in inst/
#' - commit
#' - git tag
#' - run `inst/consistent-release-tag` hook with --release-mode (passing args to hooks
#'   not possible interactively, hence we run in advance).
#' - commit and push with skipping `inst/consistent-release-tag`.
#' - autoupdate own config file
#' - bump description with dev
#' - commit and push DESCRIPTION and .pre-commit-config.yaml
#' @keywords internal
release_gh <- function(bump = "patch") {
  usethis::ui_nope("Did you prepare NEWS.md for this version?")
  autoupdate()
  if (length(unlist(git2r::status()) > 0)) {
    rlang::abort("Need clean git directory before starting release process.")
  }

  if (git2r::repository_head()$name != "master") {
    rlang::abort(paste(
      "Need to be on branch 'master' to create a release, otherwise autoudate",
      "won't use the new ref."
    ))
  }

  path_template_config <- "inst/pre-commit-config.yaml"

  old_version <- paste0("v", desc::desc_get_version())
  desc::desc_bump_version(bump)
  usethis::ui_done("Bumped version.")
  new_version <- paste0("v", desc::desc_get_version())

  update_rev_in_config(new_version, path_template_config)
  usethis::ui_done("Updated version in default config.")
  system2("./inst/consistent-release-tag", "--release-mode")
  msg <- glue::glue("Release {new_version}, see NEWS.md for details.")
  system2("git", glue::glue('commit DESCRIPTION {path_template_config} -m "{msg}"'),
    env = "SKIP=spell-check,consistent-release-tag"
  )
  usethis::ui_done("Committed DESCRIPTION and config template")
  system2("git", glue::glue('tag -a {new_version} -m "{msg}"'))
  usethis::ui_done("Tagged last commit with release version.")
  system2("git", glue::glue("push --tags"),
    env = "SKIP=consistent-release-tag"
  )
  system2("git", glue::glue("push"),
    env = "SKIP=consistent-release-tag"
  )
  usethis::ui_done("Pushed commits and tags.")
  precommit::autoupdate() # only updates if tag is on the master branch
  desc::desc_bump_version("dev")
  usethis::ui_done("Bumped version to dev")
  system2("git", glue::glue('commit DESCRIPTION .pre-commit-config.yaml -m "use latest release"'),
    env = "SKIP=spell-check"
  )

  system2("git", glue::glue("push"))
  usethis::ui_done("Committed and pushed dev version.")
}

#' Updates the hook version ref of {precommit} in a `.pre-commit-config` file
#'
#' This is useful in the release process because when releasing a new version,
#' we must make sure the template that is used with `precommit::use_precommit()`
#' is up-to date. Also, after we pushed the release to GitHub, we want to update
#' the hooks from our own hook repo in the source repo too (we could also do that
#' with `precommit::autoupdate()` though).
#' @apram new_version The version string of the new version.
#' @param path The path to a pre-commit config file.
#' @keywords internal
update_rev_in_config <- function(new_version,
                                 path = "inst/pre-commit-config.yaml") {
  config <- readLines(path)
  ours <- grep("-   repo: https://github.com/lorenzwalthert/precommit", config, fixed = TRUE)
  others <- setdiff(grep("-   repo:", config, fixed = TRUE), ours)
  next_after_ours <- others[others > ours]
  rev <- grep("rev:", config)
  our_rev <- rev[rev > ours & rev < next_after_ours]

  our_rev_without_comments <- gsub("#.*", "", config[our_rev])
  if (grepl("#", config[our_rev])) {
    rlang::warn("removed comment on rev. Please add manually")
  }
  old_version <- trimws(gsub(".*rev:", "", our_rev_without_comments))
  if (old_version == new_version) {
    message("Nothing to do, old version and new version are identical.")
  } else {
    message(glue::glue("Replacing {old_version} with {new_version} in {path}"))
    config[our_rev] <- gsub(old_version, new_version, config[our_rev])
    writeLines(config, path)
  }

}
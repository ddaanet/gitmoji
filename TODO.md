## Review state

`dev` has had the full release loop against `main`: `/simplify`, an xhigh review, a Codex adversarial review, a second xhigh review of the commits added after it, the fix commit for that review, and one medium pass on that fix whose findings were all declined (rare states, low).

## Remaining

- Release gitmoji 0.6.0 (`just release minor`). `origin/main` carries a pre-amend copy of an earlier `dev` tip that is not an ancestor of `dev`, so moving `origin/main` to the release needs a force-push (approved by my human partner).

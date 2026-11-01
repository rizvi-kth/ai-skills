[env("JUST_TIMESTAMP", "true")]
gpush _commit_message:
    git status
    git add .
    git commit -m "{{_commit_message}}"
    git push
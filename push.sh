#!/bin/bash

commitMessage=""

getCommitMessage() {
    read -p "Enter Commit Message: " commitMessage

    if test -z "$commitMessage"; then
        getCommitMessage
    fi
}

getCommitMessage
echo $commitMessage

git add .
git commit -m "${commitMessage}"
git push -u origin master

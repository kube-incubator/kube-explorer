#!/bin/sh

git remote add upstream https://github.com/kube-incubator/kube-explorer
git fetch upstream
git checkout master
git rebase upstream/master
git push -f origin master
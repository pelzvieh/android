#!/usr/bin/env bash

#1: GIT_USERNAME
#2: GIT_TOKEN
#3: BRANCH
#4: LOG_USERNAME
#5: LOG_PASSWORD
#6: DRONE_BUILD_NUMBER
#7: PULL_REQUEST_NUMBER

stableBranch="master"
repository="android"

ruby scripts/analysis/lint-up.rb $1 $2 $3
lintValue=$?

curl 2>/dev/null "https://www.kaminsky.me/nc-dev/$repository-findbugs/$stableBranch.xml" -o "/tmp/$stableBranch.xml"
ruby scripts/analysis/spotbugs-up.rb "$3"
spotbugsValue=$?

# exit codes:
# 0: count was reduced
# 1: count was increased
# 2: count stayed the same

echo "Branch: $3"

if [ $3 = $stableBranch ]; then
    echo "New spotbugs result for $stableBranch at: https://www.kaminsky.me/nc-dev/$repository-findbugs/$stableBranch.html"
    curl -u $4:$5 -X PUT https://nextcloud.kaminsky.me/remote.php/webdav/$repository-findbugs/$stableBranch.html --upload-file app/build/reports/spotbugs/spotbugs.html
    curl 2>/dev/null -u "$4:$5" -X PUT "https://nextcloud.kaminsky.me/remote.php/webdav/$repository-findbugs/$stableBranch.xml" --upload-file app/build/reports/spotbugs/gplayDebug.xml

    if [ $lintValue -ne 1 ]; then
        echo "New lint result for $stableBranch at: https://www.kaminsky.me/nc-dev/$repository-lint/$stableBranch.html"
        curl -u $4:$5 -X PUT https://nextcloud.kaminsky.me/remote.php/webdav/$repository-lint/$stableBranch.html --upload-file app/build/reports/lint/lint.html
        exit 0
    fi
else
    if [ -e $6 ]; then
        6=$stableBranch"-"$(date +%F)
    fi
    echo "New lint results at https://www.kaminsky.me/nc-dev/$repository-lint/$6.html"
    curl 2>/dev/null -u $4:$5 -X PUT https://nextcloud.kaminsky.me/remote.php/webdav/$repository-lint/$6.html --upload-file app/build/reports/lint/lint.html

    echo "New spotbugs results at https://www.kaminsky.me/nc-dev/$repository-findbugs/$6.html"
    curl 2>/dev/null -u $4:$5 -X PUT https://nextcloud.kaminsky.me/remote.php/webdav/$repository-findbugs/$6.html --upload-file app/build/reports/spotbugs/spotbugs.html

    # delete all old comments, starting with Codacy
    oldComments=$(curl 2>/dev/null -u $1:$2 -X GET https://api.github.com/repos/nextcloud/android/issues/$7/comments | jq '.[] | (.id |tostring) + "|" + (.user.login | test("nextcloud-android-bot") | tostring) + "|" + (.body | test("<h1>Codacy.*") | tostring)'  | grep "true|true" | tr -d "\"" | cut -f1 -d"|")

    echo $oldComments | while read comment ; do
        curl 2>/dev/null -u $1:$2 -X DELETE https://api.github.com/repos/nextcloud/android/issues/comments/$comment
    done

    # check library, only if base branch is master
    baseBranch=$(scripts/analysis/getBranchBase.sh $1 $2 $7 | tr -d "\"")
    if [ $baseBranch = "master" -a $(grep "androidLibraryVersion = \"master-SNAPSHOT\"" build.gradle -c) -ne 1 ]; then
        checkLibraryMessage="<h1>Android-library is not set to master branch in build.gradle</h1>"
        checkLibrary=1
    elif [ $baseBranch != "master" -a $baseBranch = $stableBranch -a $(grep "androidLibraryVersion.*SNAPSHOT" build.gradle -c) -ne 0 ]; then
        checkLibraryMessage="<h1>Android-library is set to a SNAPSHOT in build.gradle</h1>"
        checkLibrary=1
    else
        checkLibrary=0
    fi

    # lint and spotbugs file must exist
    if [ ! -s app/build/reports/lint/lint.html ] ; then
        echo "lint.html file is missing!"
        exit 1
    fi

    if [ ! -s app/build/reports/spotbugs/spotbugs.html ] ; then
        echo "spotbugs.html file is missing!"
        exit 1
    fi

    # add comment with results
    lintResultNew=$(grep "Lint Report.* [0-9]* warning" app/build/reports/lint/lint.html | cut -f2 -d':' |cut -f1 -d'<')

    lintErrorNew=$(echo $lintResultNew | grep "[0-9]* error" -o | cut -f1 -d" ")
    if ( [ -z $lintErrorNew ] ); then
        lintErrorNew=0
    fi

    lintWarningNew=$(echo $lintResultNew | grep "[0-9]* warning" -o | cut -f1 -d" ")
    if ( [ -z $lintWarningNew ] ); then
        lintWarningNew=0
    fi

    lintResultOld=$(curl 2>/dev/null https://raw.githubusercontent.com/nextcloud/android/$stableBranch/scripts/analysis/lint-results.txt)
    lintErrorOld=$(echo $lintResultOld | grep "[0-9]* error" -o | cut -f1 -d" ")
    if ( [ -z $lintErrorOld ] ); then
        lintErrorOld=0
    fi

    lintWarningOld=$(echo $lintResultOld | grep "[0-9]* warning" -o | cut -f1 -d" ")
    if ( [ -z $lintWarningOld ] ); then
        lintWarningOld=0
    fi

    if [ $stableBranch = "master" ] ; then
        codacyValue=$(curl 2>/dev/null https://app.codacy.com/dashboards/breakdown\?projectId\=44248 | grep "total issues" | cut -d">" -f3 | cut -d"<" -f1)
        codacyResult="<h1>Codacy</h1>$codacyValue"
    else
        codacyResult=""
    fi

    lintResult="<h1>Lint</h1><table width='500' cellpadding='5' cellspacing='2'><tr class='tablerow0'><td>Type</td><td><a href='https://www.kaminsky.me/nc-dev/"$repository"-lint/"$stableBranch".html'>$stableBranch</a></td><td><a href='https://www.kaminsky.me/nc-dev/"$repository"-lint/"$6".html'>PR</a></td></tr><tr class='tablerow1'><td>Warnings</td><td>"$lintWarningOld"</td><td>"$lintWarningNew"</td></tr><tr class='tablerow0'><td>Errors</td><td>"$lintErrorOld"</td><td>"$lintErrorNew"</td></tr></table>"

    spotbugsResult="<h1>SpotBugs</h1>$(scripts/analysis/spotbugsComparison.py "/tmp/$stableBranch.xml" app/build/reports/spotbugs/gplayDebug.xml --link-new "https://www.kaminsky.me/nc-dev/$repository-findbugs/$6.html" --link-base "https://www.kaminsky.me/nc-dev/$repository-findbugs/$stableBranch.html")"

    if ( [ $lintValue -eq 1 ] ) ; then
        lintMessage="<h1>Lint increased!</h1>"
    fi

    if ( [ $spotbugsValue -eq 1 ] ) ; then
        spotbugsMessage="<h1>SpotBugs increased!</h1>"
    fi

    # check gplay limitation: all changelog files must only have 500 chars
    gplayLimitation=$(scripts/checkGplayLimitation.sh)

    if [ ! -z "$gplayLimitation" ]; then
        gplayLimitation="<h1>Following files are beyond 500 char limit:</h1><br><br>"$gplayLimitation
    fi

    # check for NotNull
    if [[ $(grep org.jetbrains.annotations app/src/main/* -irl | wc -l) -gt 0 ]] ; then
        notNull="org.jetbrains.annotations.NotNull is used. Please use androidx.annotation.NonNull instead.<br><br>"
    fi

    payload="{ \"body\" : \"$codacyResult $lintResult $spotbugsResult $checkLibraryMessage $lintMessage $spotbugsMessage $gplayLimitation $notNull\" }"
    curl -u "$1:$2" -X POST "https://api.github.com/repos/nextcloud/android/issues/$7/comments" -d "$payload"

    if [ ! -z "$gplayLimitation" ]; then
        exit 1
    fi

    if [ $checkLibrary -eq 1 ]; then
        exit 1
    fi

    if [ ! $lintValue -eq 2 ]; then
        exit $lintValue
    fi

    if [ -n "$notNull" ]; then
        exit 1
    fi

    if [ $spotbugsValue -eq 2 ]; then
        exit 0
    else
        exit $spotbugsValue
    fi
fi

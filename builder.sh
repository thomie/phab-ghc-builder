#!/usr/bin/env bash

set -e

BUILDID=$1
DIFF=$2
REVISION=$3
PHID=$4

if [[ -z "$BUILDID" ]] || [[ -z "$DIFF" ]] || [[ -z "$REVISION" ]] || [[ -z "$PHID" ]]; then
  echo "err: usage - ./builder.sh <build-id> <diff-id> <revision> <phid>"
  exit 1
fi

# Create a build directory
cd /srv/ghc-builds
rm -rf ghc
git clone --recursive git://git.haskell.org/ghc.git
cd ghc

# Apply patch, perform build
#arc patch --nobranch --diff $DIFF
NUM_CPUS=3 # TODO FIXME
CPUS=$NUM_CPUS ./validate 2>&1 > ./validate.log
BUILDRES=$?

## -- Upload result file
LOGS=`cat ./validate.log | base64`
FILEMSG="{\"data_base64\":\"$LOGS\",\"name\":\"ghc-build-B$BUILDID-D$REVISION-d$DIFF.txt\"}"
# Get PHID from response
PHID=`echo '$FILEMSG' | arc call-conduit file.upload | jq '.response'`
FILEMSG2="{\"phid\":$PHID}"
# Get File identifier
FID=`echo '$FILEMSG2' | arc call-conduit file.info | jq '.response.id | tonumber'`
FILEID="{F$FID}"

# Post back to Harbormaster about the build status
PASSMSG="{\"buildTargetPHID\":\"$PHID\",\"type\":\"pass\"}"
FAILMSG="{\"buildTargetPHID\":\"$PHID\",\"type\":\"fail\"}"

if [ "x$BUILDRES" = "x0" ];
  echo "'$PASSMSG'" | arc call-conduit harbormaster.sendmessage
else
  echo "'$FAILMSG'" | arc call-conduit harbormaster.sendmessage
fi

# Post passing/failing comment on the revision.
PASSMSG="Yay! Build B$BUILDID (D$REVISION, Diff $DIFF) has **succeeded**! Full logs available at {$FILEID}."
FAILMSG="Whoops, Build B$BUILDID (D$REVISION, Diff $DIFF) has **failed**! Full logs available at {$FILEID}."

if [ "x$BUILDRES" = "x0" ];
  echo "'{\"revision_id\":\"$REVISION\",\"message\":\"$PASSMSG\"}'" \
    | arc call-conduit differential.createcomment
else
  echo "'{\"revision_id\":\"$REVISION\",\"message\":\"$FAILMSG\"}'" \
    | arc call-conduit differential.createcomment
fi

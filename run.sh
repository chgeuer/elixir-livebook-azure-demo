#!/bin/bash

targetFolder=/mnt/c/Users/chgeuer/Desktop/storagedemo

mkdir "${targetFolder}"

cp "/mnt/c/Users/chgeuer/Videos/This Is Spinal Tap - These go to 11.mpg-KOO5S4vxi0o.mp4" "${targetFolder}/TheseGoToEleven.mp4"

docker run -p 8080:8080 --pull always -u "$(id -u):$(id -g)" -v "${targetFolder}:/data" "livebook/livebook"

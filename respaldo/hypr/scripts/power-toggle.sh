#!/bin/bash
current=$(powerprofilesctl get)
if [ "$current" = "performance" ]; then
  powerprofilesctl set balanced
else
  powerprofilesctl set performance
fi

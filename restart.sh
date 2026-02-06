#!/bin/bash

systemctl --user daemon-reload
systemctl --user restart brain.service
systemctl --user status brain.service

journalctl --user -u brain.service -f

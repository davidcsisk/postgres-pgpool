#!/bin/bash
eval $(ssh-agent) && ssh-add ~/.ssh/bastion.pem && ssh-add ~/.ssh/jira-datacenter.pem 
PS1="[\u@\h:ssh-agent \W]$ " bash --norc
kill $SSH_AGENT_PID

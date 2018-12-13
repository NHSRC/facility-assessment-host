# facility-assessment-host

### Prerequisites
1. Java 1.8
2. Python 2.7 or 3.3+

### Setup
1. Configure `sshd` for only key-based logins (Disable password auth)
2. Disallow ssh access to `root`
3. Create login user `sam` and give `sudo` privileges:
    * `adduser --ingroup admin --home /home/sam sam` 
    * (adding to `admin` group provides sudo privileges)
4. Change timezone of server to IST with `dpkg-reconfigure tzdata`
5. Create service user `app`
    * `adduser --system --group --disabled-password --home /home/app --shell /bin/bash app`
6. For convenience, add user `sam` to group `app`
    * `adduser sam app`
7. To be able to bind to privileged ports (less than 1024), do 
    * `setcap cap_net_bind_service+ep /path/to/bin/java` 
    * (see https://confluence.atlassian.com/confkb/permission-denied-error-when-binding-a-port-290750651.html)
8. Create approp. directory in s3://samanvay/client-backups/ 
9. `cd /home/app`
10. `git clone <this-repo>`    
11. `cd <this-repo>/scripts/deployment`
12. `sudo ./setup-all`
13. Enter credentials of `backupper` IAM user during aws configuration

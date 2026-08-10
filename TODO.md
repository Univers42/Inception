- [] check if we use docker-compose
- [] is each docker image have the same name as its corresponding service ?
- [] Is each service running in a dedicated container ?
- [] Is it the penultimate version of the OS we're using?
- [] did we write our own dockerfiles ? are they being called from docker-compose.yml by our makefile?
- [] Verify that we never pull ready-made Docker images, as well as using services such as DockerHub (Alpine/Debian being excluded from this rule)
- [] Do we have a docker container NGINX with TLSv1.2 or TLSV1.3 only?
- [] A docker container that contains Wordpress + php-fpm (it must be installed and configured) only, without nginx
- [] A docker container that contains MariaDB only, without nginx.
- [] A volume that contain our WordPress datbaase.
- [] A second volume that contains our wordpress website files
- [] we must use Docekr named volmes for these two persistent storages. Bind mounts are not allowed for these volumes
- [] both names volumes must store their data inside /home/login/data on the host mounts are not allow for these volumes
- [] both names volumes must store their data inside /home/login/data on the host machine. Reaplace "login" weith our learneer's username
- [] a docker-network that establishes the connection between our containers
- [] cause a crash with by create mutant files or something like that and veirfy that the container restart in case of a crash.. or cause a crash sending a signal to create the said bug..
- [] A docker container is not a virtual machine. So we need to verify to verify that we don't use any hacky  patches based on tail -f and similar method when trying to run it. Write a doocumentation why it's a wrong practice with reference of official documentation that say that..
- [] verify that we don't use the command host or --link or links because they are forbiden. 
- [] The network line must be presnt in our docker-compose.yml file.
- []The container must not be started witha command running an infinite loop (create the bug and see what happen) to see if the program defend well onf that This also applies to any command used as entrypoiint, or used in  entrpoint scripts. The following are a few prohibited has¡cky patches: tail -f, bash, sleep infinity, while true
- [] in our wordpress dtabase, there must be two users, one of them being the administrator. The administator's username can't contain Admin/Admin or administrator/Administrator //e.g., admin, administrator, Administrator, admin-123, and so forth..
- [] The volumes will be available in the /home/login/data folder of the host machines using docker. Of course we have to replace the login with ours. 
- [] we have to configure our doman name so it points ot our local IP address. (dynamically I guess) this domain name must be login.42.fr. Again, we have to use our own login, for example, if our login is wil, wil.42.fr, will redirect to the IP address pointing to wil's website.
- [] The latest tag is prohibites.
- [] no password must be present in dockerfiles.
- [] it mandatory t use environment variables
- [] it is strongly recommended that we use Docker secrets to store andy credential information
- [] NGINX container must be the only entrypoint into our infrastructure via the port 443 only, using the TLSv1.2 or TLSv1.3 protocol
- [] below is an example of the expected directoyr structure
```bash
$> ls -alR
total XX
drwxrwxr-x 3 wil wil 4096 avril 42 20:42 .
drwxrwxrwt 17 wil wil 4096 avril 42 20:42 ..
-rw-rw-r-- 1 wil wil XXXX avril 42 20:42 Makefile
drwxrwxr-x 3 wil wil 4096 avril 42 20:42 secrets
drwxrwxr-x 3 wil wil 4096 avril 42 20:42 srcs
./secrets:
total XX
drwxrwxr-x 2 wil wil 4096 avril 42 20:42 .
drwxrwxr-x 6 wil wil 4096 avril 42 20:42 ..
-rw-r--r-- 1 wil wil XXXX avril 42 20:42 credentials.txt
-rw-r--r-- 1 wil wil XXXX avril 42 20:42 db_password.txt
-rw-r--r-- 1 wil wil XXXX avril 42 20:42 db_root_password.txt
./srcs:
total XX
drwxrwxr-x 3 wil wil 4096 avril 42 20:42 .
drwxrwxr-x 3 wil wil 4096 avril 42 20:42 ..
-rw-rw-r-- 1 wil wil XXXX avril 42 20:42 docker-compose.yml
-rw-rw-r-- 1 wil wil XXXX avril 42 20:42 .env
drwxrwxr-x 5 wil wil 4096 avril 42 20:42 requirements
./srcs/requirements:
total XX
drwxrwxr-x 5 wil wil 4096 avril 42 20:42 .
drwxrwxr-x 3 wil wil 4096 avril 42 20:42 ..
drwxrwxr-x 4 wil wil 4096 avril 42 20:42 bonus
drwxrwxr-x 4 wil wil 4096 avril 42 20:42 mariadb
drwxrwxr-x 4 wil wil 4096 avril 42 20:42 nginx
drwxrwxr-x 4 wil wil 4096 avril 42 20:42 tools
drwxrwxr-x 4 wil wil 4096 avril 42 20:42 wordpress
./srcs/requirements/mariadb:
total XX
drwxrwxr-x 4 wil wil 4096 avril 42 20:45 .
drwxrwxr-x 5 wil wil 4096 avril 42 20:42 ..
drwxrwxr-x 2 wil wil 4096 avril 42 20:42 conf
-rw-rw-r-- 1 wil wil XXXX avril 42 20:42 Dockerfile
-rw-rw-r-- 1 wil wil XXXX avril 42 20:42 .dockerignore
drwxrwxr-x 2 wil wil 4096 avril 42 20:42 tools
[...]
./srcs/requirements/nginx:
total XX
drwxrwxr-x 4 wil wil 4096 avril 42 20:42 .
drwxrwxr-x 5 wil wil 4096 avril 42 20:42 ..
drwxrwxr-x 2 wil wil 4096 avril 42 20:42 conf
-rw-rw-r-- 1 wil wil XXXX avril 42 20:42 Dockerfile
-rw-rw-r-- 1 wil wil XXXX avril 42 20:42 .dockerignore
drwxrwxr-x 2 wil wil 4096 avril 42 20:42 tools
[...]
$> cat srcs/.env
DOMAIN_NAME=wil.42.fr
# MYSQL SETUP
MYSQL_USER=XXXXXXXXXXXX
[...]
$>
```
- [] any credentials, api keys, passwords, etc. must be saved locally in various ways/files and ignored by git. 
- [] We stored our variables (as a domain name) in an envrionoment variable file like .env


## Bonus
- [] A dockerfile must be written fore ach additional service. this each service will run inside its own container and will have, if necessary, its dedicated volume.
- [] set up redis cached for our wordpress website n order to properly manage the cache.
- [] Set up a FTP server container pointing to the volume of our wordpress website.
- [] Create a simple static website (PHP exclusded) for instance a  bloc. A showcase of website presenting our project...
- [] set up Adminer
- [] set up a service of our choice taht we think is useful. During the defense, we will have to justify our choice.

- [] to commplete the bonus part we have the possibility to set up exrta service. i thicase we need to open more ports to suit the needs.

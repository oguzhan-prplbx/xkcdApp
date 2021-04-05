# Ultimate Guide to Deploying Django at Scale on AWS Elastic Container Service


## Overview


### problems:
session
database
logs


### Pre requisites

we are going to use [xkcd library](https://pypi.org/project/xkcd/#description)

Writing XKCD Django App
0. creating virtualenvironment
1. installing django
2. creating & migrating our models 
3. adding homepage view
4. configuring urls
5. writing the HTML
6. Dockerizing our application
7. serving django with gunicorn on docker
AWS
1. creating parameter store
2. RDS security group & RDS Creation
3. Moving our app secrets to Parameter Store
4. uploading our docker image to ECR
5. deploying to ECS Fargate + hey benchmark
6. creating an ELB (ECS will only accept requests from ELB's security group.)
7. enabling HTTPS with ACM
8. Route53 configuration

## Implementing XKCD App

### Creating and activating virtual environment
```bash
# install the virtualenv package
pip install virtualenv

#create a virtualenv with the name venv
virtualenv venv

# activate virtualenv on windows
cd venv/Scripts
activate

# activate virtualenv on linux
./venv/bin/activate
```

### Installing Django

```bash
# install django and xkcd python library
pip install django xkcd

# create a django project name xkcd_app
django-admin startproject xkcd_app

# you should get the following files created
xkcd_app
├── manage.py
└── xkcd_app
    ├── asgi.py
    ├── __init__.py
    ├── settings.py
    ├── urls.py
    └── wsgi.py
```


Let's review and change the `xkcd_app/settings.py`

```python
# /xkcd_app/xkcd_app/settings.py

# allow any host for now
ALLOWED_HOSTS = ['*']

# add our app to installed apps
INSTALLED_APPS = [
    .
    .
    'django.contrib.staticfiles',
    'xkcd_app'
]
```

#### creating database models
Let's create our models. First we have to create a file named `models.py` on our `xkcd_app` folder.

```python
# /xkcd_app/xkcd_app/models.py
from django.db import models

class XKCDComicViews(models.Model):
    comic_number = models.IntegerField(primary_key=True, unique=True)
    view_count = models.IntegerField(default=0)
```

Let's migrate `XKCDComicViews` model to our database. Django will use sqlite3 by default for local development. 
```bash
# first apply default migrations
python manage.py migrate

# create our django apps migrations
python manage.py makemigrations xkcd_app

# and migrate them
python manage.py migrate xkcd_app
```

#### adding models to django admin page

create a `admin.py` file under `xkcd_app/xkcd_app`

```python
#xkcd_app/xkcd_app/admin.py
from django.contrib import admin
from .models import XKCDComicViews

admin.site.register(XKCDComicViews)
```

#### creating homepage view
Let's create `views.py` under our xkcd_app.

```python
# /xkcd_app/xkcd_app/views.py
from django.shortcuts import render
from .models import XKCDComicViews
import xkcd

def get_comic_and_increase_view_count(comic_number, increase_by=1):
    # get or create this with given comic_number
    comic, _ = XKCDComicViews.objects.get_or_create(pk=comic_number)
    comic.view_count += increase_by # increase the view_count
    comic.save() # save it

def homepage(request):
    # get a random comic from xkcd lib.
    random_comic = xkcd.getRandomComic()
    # increase it's view count
    get_comic_and_increase_view_count(random_comic.number, increase_by=1)
    # create a context to render the html with.
    context = {
        "number": random_comic.number,
        "image_link": random_comic.getImageLink(),
        "title": random_comic.getTitle(),
        "alt_text": random_comic.getAltText()
    }
    # return rendered html.
    return render(request, 'xkcd_app/homepage.html', context)

```
#### adding homepage view to urls.py
```python
# /xkcd_app/xkcd_app/urls.py
from django.contrib import admin
from django.urls import path
from .views import homepage
urlpatterns = [
    path('admin/', admin.site.urls),
    path('', homepage, name='homepage')
]
```
#### creating homepage.html

```html
<!-- /xkcd_app/xkcd_app/templates/xkcd_app/homepage.html -->
<html>
<head>
<title>XKCD App</title>
<link rel="stylesheet" href="https://stackpath.bootstrapcdn.com/bootstrap/4.5.2/css/bootstrap.min.css" integrity="sha384-JcKb8q3iqJ61gNV9KGb8thSsNjpSL0n8PARn9HuZOnIxN0hoP+VmmDGMN5t9UJ0Z" crossorigin="anonymous">
</head>
<body>
  <div class="container">
    <div class="row" style="margin-top:15px">
        <div class="col-sm-8 mx-auto">
            <div class="col text-center">
                <h2 class="header" >#{{number}} | {{title}}</h2>
            <hr/>
            <img src="{{image_link}}" class="img-fluid" alt="{{alt_text}}" />
            <hr/>
                <a class="btn btn-default" href="{% url 'homepage' %}">Another One</a>
            </div>
        </div>
    </div>
<script src="https://stackpath.bootstrapcdn.com/bootstrap/4.5.2/js/bootstrap.min.js" integrity="sha384-B4gt1jrGC7Jh4AgTPSdUtOBvfO8shuf57BaghqFfPlYxofvL8/KUEfYiJOMMV+rV" crossorigin="anonymous"></script>
</body>
</html>
```

#### creating requirements.txt file

Freeze the python requirements and move the file to root directory of the project. 

```bash
# cd into the root directory of the project and then run the command below 

# be sure to activate the virtual env
pip freeze > requirements.txt
```
For this project the requirements.txt should look like this:
```txt
boto3
xkcd
django
psycopg2-binary
gunicorn
django-redis
```

### Dockerizing our Django App

Create a `Dockerfile` on the root directory of the project.

```Dockerfile
# /Dockerfile
FROM python:3.8
# PYTHONUNBUFFERED variable is used for non-buffered stdout
ENV PYTHONUNBUFFERED=1

# changing our working directory to be /opt
WORKDIR /opt

# copying and installing python requirements
COPY requirements.txt requirements.txt
RUN pip install -r requirements.txt

# copying the entire django application
COPY xkcd_app/ .

# exposing our django port: 8000
EXPOSE 8000

# serving django with gunicorn on port 8000 (1 worker, timeout of 15 secs)
CMD ["gunicorn", "--bind", "0.0.0.0:8000", "--workers", "1", "--timeout", "15", "xkcd_app.wsgi"]
```

#### testing the Docker Image

Let's build and run our docker image.

```bash
# build the image with the latest tag
docker build -t xkcd:latest .  

# run the image with port mapping 8000 to 8000
docker run -p 8000:8000 xkcd:latest

# output should look something like this.
# ... [1] [INFO] Starting gunicorn 20.1.0
# ... [1] [INFO] Listening at: http://0.0.0.0:8000 (1)
# ... [1] [INFO] Using worker: sync
# ... [8] [INFO] Booting worker with pid: 8
```
If everything goes well, you can go to [http://0.0.0.0:8000](http://0.0.0.0:8000) or [http://localhost:8000](http://localhost:8000) to see XKCD app working.



## AWS

### AWS RDS - Relational Database Service
#### configuring RDS Security Group
On AWS Console, go to `Security Groups` under the `VPC` service. Press Create Security Group button.

![RDS Security Group Creation](assets/aws/rds_sg_creation.png)
| Setting | Option |
|-- |-- |
| Name | xkcdAppRDSSecurityGroup |
| Description | Allows access on PostgreSQL port: 5432. |
| VPC | Select your VPC, or use the default one. |
| Inbound Rules | Type: `PostgreSQL`, Source: `Anywhere` |
| Outbound Rules | Type: `All Trafic`, Destination: `Anywhere` |


#### creating a Postgresql Database on RDS 
On AWS Console, go to `RDS` and start to create a new RDS instance. RDS creation settings below uses default VPC and Free-tier. Feel free to change the configuration according to your requirements.
<details open>
  <summary> <b> Table of Configuration </b></summary>

|Setting  | Option | Detail |
| -- | -- | -- | 
| Creation Method | Standart create | |
| Engine Option | PostgreSQL | |
| Engine Version | 12.5-R1 | Specify your DB engine version. |
| Templates | Free Tier | If you are building for prod or test envs, choose respectively.|
| DB Instance Identifier | xkcdappdb | |
| Master Username | postgres | |
| Master Password | < redacted > | |
| DB Instance Class | db.t2.micro | you can upgrade the instance class to your needs. |
| Storage Type| General Purpose(SSD) | |
| Allocated Storage | 20GB | |
| Enable Storage Autoscaling | False | You can enable this if you need it. |
| Multi-AZ Deployment | False | This feature not included in the free-tier. Production environments would benefit from this feature. |
| VPC | Default VPC | Ideally you should create your own VPC and choose that. |
| Subnet Group | default | |
| Public Access | Yes | We will turn this feature off later. We need public access only in the first setup to test things. |
| VPC Security Group |Delete default and choose existing: `xkcdAppRDSSecurityGroup` | |
| Availability Zone | eu-west-2a | Choose one AZ if you are on free-tier.|
| Database Authentication | Password Authentication | |
| Initial Database Name | xkcd_test_db | **Initial Database Name** field has to be filled or the AWS will not create a database inside the RDS instance. If you fail to fill this field, you will have to manually create the database.|

</details>


<details>
  <summary> <b> Database Engine </b></summary>

![Choosing Database Engine: PostgreSQL](assets/aws/rds_1.png)

</details>
<details>
  <summary> <b> RDS Creation Template </b></summary>

![Selecting Template: Standard](assets/aws/rds_2.png)

</details>
<details>
  <summary> <b> Database Settings and Credentials </b></summary>

![Selecting Template: Standard](assets/aws/rds_3.png)

</details>

<details>
  <summary><b> Database Instance Class  </b></summary>

![Database Instance Class: t2.micro](assets/aws/rds_4.png)

</details>
<details>
  <summary><b> Database Storage </b></summary>

![Database Storage: 20GB SSD](assets/aws/rds_5.png)

</details>
<details>
  <summary><b> Connectivity  </b></summary>

Be sure to select Public Access: Yes. We will need to access the database publicly in the first setup, but we will turn it off later.
![Database Connectivity Settings](assets/aws/rds_7.png)

</details>
<details>
  <summary><b>  Database Authentication </b></summary>

![Database Authentication: Password authentication](assets/aws/rds_8.png)

</details>
<details open>
  <summary><b> Additional Configuration  </b></summary>


</br>

> **_NOTE:_**  **Initial Database Name** field has to be filled or the AWS will not create a database inside the RDS instance you are creating. If you fail to fill this field, you will have to manually create the database.


![Additional Configuration](assets/aws/rds_9.png)

</details>

</details>
<details>
  <summary><b>  Acquiring the Database Connection Endpoint </b></summary>

Wait for the database creation to be complete. Go to `xkcdappdb` on `RDS > Databases` and then go to `Connectivity & Security` tab. 

</details>

#### updating django settings to use the PostgreSQL Database Backend

##### install the PostgreSQL library
```bash
# be sure to activate the venv environment
pip install psycopg2-binary
```


##### update the settings.py
```python
#/xkcd_app/xkcd_app/settings.py
import os

DATABASES = {
    'default': {
        'ENGINE': 'django.db.backends.postgresql',
        'NAME': os.environ.get('DATABASE_NAME'),
        'USER': os.environ.get('DATABASE_USER'),
        'PASSWORD': os.environ.get('DATABASE_PASSWORD'),
        'HOST': os.environ.get('DATABASE_HOST'),
        'PORT': '5432'
    }
}

```

Using environment variables for application configuration **is not a secure way** of doing things. Integrating AWS Parameter Store to our `settings.py` file is something easy. Let's configure AWS Systems Manager Parameter Store for XKCD App.

### Parameter Store

Go to `Parameter Store` under `AWS Systems Manager` and click on **Create Parameter**.

Parameter Store lets you create categorized paramater names, so you can have different parameters for different apps or app environments.
#### adding our secrets to parameter store
For **DATABASE_NAME** parameter, you can create a parameter as following:

![AWS Parameter Store adding DATABASE_NAME as a parameter](assets/aws/aws_parameter_store_add.png)
| Setting | Option | Detail |
| --| --| --|
| Name | xkcdapp/test/DATABASE_NAME | app and environment categorized parameter name |
| Description | xkcd app RDS test DB identifier | |
| Tier | Standard | |
| Type | SecureString | This type of parameters are going to be encrypted while sitting. |
| KMS key source | My Current Account |  |
| KMS Key ID | alias/aws/ssm | Choose the default AWS managed key. This will allow ECS containers to access to parameters without further configuration. |
| Value | xkcddb_test_db  | Type the database name you gave in the RDS Creation: Additional Configuration step. |

Follow the same steps to add the remaining database connection credentials to paramater store. You may also want to add `SECRET_KEY` variable generated for your Django project. Django's `SECRET_KEY` is used for encryption inside Django. 

When you are finished with adding the secrets, you should see something like this on Parameter Store Console.

![Parameter Store Console](assets/aws/parameter_store_complete.png)

You can check the existence of parameters with AWS CLI, if you have it set up.
```bash
aws ssm get-parameters --name "/xkcdapp/test/DATABASE_HOST" --with-decryption --region <your_region> --profile <your_aws_cli_profile>
```

#### configuring Django App to use AWS Parameter Store

##### install AWS SDK for Python: boto3
```bash
# be sure to be in the venv virtual environment
pip install boto3
```
##### update the settings.py file

```python
# xkcd_app/xkcd_app/settings.py
import boto3
ssm = boto3.client('ssm', region_name='eu-west-2')

prefix = 'xkcdapp'
env = 'test'
prefixenv = f"/{prefix}/{env}/"

SECRET_KEY = ssm.get_parameter(Name=prefixenv + "DJANGO_SECRET_KEY", WithDecryption=True)['Parameter']['Value'] 

DATABASES = {
    'default': {
        'ENGINE': 'django.db.backends.postgresql',
        'NAME': ssm.get_parameter(Name=prefixenv + "DATABASE_NAME", WithDecryption=True)['Parameter']['Value'],
        'USER': ssm.get_parameter(Name=prefixenv + "DATABASE_USER", WithDecryption=True)['Parameter']['Value'],
        'PASSWORD': ssm.get_parameter(Name=prefixenv + "DATABASE_PASSWORD", WithDecryption=True)['Parameter']['Value'],
        'HOST': ssm.get_parameter(Name=prefixenv + "DATABASE_HOST", WithDecryption=True)['Parameter']['Value'],
        'PORT': '5432'
    }
}
```

#### migrating django models to RDS instance

> **_NOTE:_** : Be sure that your AWS Accounts credentials are set in the AWS CLI's `credentials` file.

Migrate our migrations to AWS RDS.
```bash
python manage.py migrate

# Operations to perform:
#   Apply all migrations: admin, auth, contenttypes, sessions, xkcd_app
# Running migrations:
#   Applying contenttypes.0001_initial... OK
#   Applying auth.0001_initial... OK
#   .
#   .
#   Applying sessions.0001_initial... OK
#   Applying xkcd_app.0001_initial... OK
```
#####


##### run the docker image with the aws credentials
If you want to build and test the docker image with the application secrets on the AWS Parameter Store:
1. build the image again to apply the `settings.py` file changes to docker image.
2. run the image with `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` environment variables set. 
```bash
# build the image again
docker build -t xkcd:latest .  

# run with AWS credentials set in the environment variables.
docker run -p 8000:8000 -e AWS_ACCESS_KEY_ID='XXXXXXXXXXXX' -e AWS_SECRET_ACCESS_KEY='YYYYYYYYYYY' xkcd:latest
```



#### creating parameter store IAM Role
Go to `Roles` under `AWS IAM` and  click on **Create Role**.

Select the _System Manager_ use case.

![AWS IAM Role Creation System Manager use case ](assets/aws/ssm_iam_role_use_case.png)

Click on _Next: Permissions_ and then `Create Policy`.

![AWS IAM Role Creation Inline Policy JSON ](assets/aws/parameter_store_role_policy_creation.png)

Copy and paste the following AWS IAM Policy to editor and hit next.

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "AllowSSMAccess",
            "Effect": "Allow",
            "Action": [
                "ssm:PutParameter",
                "ssm:DeleteParameter",
                "ssm:GetParameterHistory",
                "ssm:GetParametersByPath",
                "ssm:GetParameters",
                "ssm:GetParameter",
                "ssm:DescribeParameters",
                "ssm:DeleteParameters"
            ],
            "Resource": "arn:aws:ssm:*:*:parameter/*"
        }
    ]
}
```

Give a name and description to Parameter Store access role.

![AWS IAM Role Creation Inline Policy JSON ](assets/aws/parameter_store_creating_role_policy.png)

|Setting  |Option | 
| -- | -- | 
| Name | SystemsManagerParameterStoreFullAccess | 
| Description | Systems Manager Parameter Store Full Access Role. | 

We will be attaching this IAM Role to ECS containers we are going to run to allow them to read the parameters.


#####creating a super user
```bash
python3 manage.py createsuperuser
```


### ElastiCache Redis

#### Creating the Security Group: XKCDAppElastiCacheSecurityGroup

![Elasti Cache Redis Security Group Creation](assets/aws/elasticache_sg.png)

| Setting | Option |
|-- |-- |
| Name | XKCDAppElastiCacheSecurityGroup |
| Description | XKCD Apps elasti cache security group. Allows access from port:  6379 |
| VPC | Select your VPC, or use the default one. |
| Inbound Rules | Type: `CustomTCP`, Port Range: `6379`, Source: `Anywhere` |
| Outbound Rules | Type: `All Trafic`, Destination: `Anywhere` |

#### Creating the ElastiCache Redis Instance
Go to `Redis` under `ElastiCache` and press create button.


<details open>
  <summary><b> Table of Configuration </b></summary>

| Setting | Option | Detail |
| --| --| --|
| Cluster Engine | Redis, Cluster Mode Disabled |  |
| Location | Amazon Cloud | |
| Name | xkcdappredis | |
| Description| Session storage for XKCD App | |
|Engine version compatibility | 6.x | |
| Port| **6379**| |
| Parameter group| default.redis6.x| |
| Node type| **cache.t2.micro (0.5 GiB)** | |
| Number of replicas| 0 | |
| Multi-AZ | False | |
| Subnet Group| Create new| |
| Subnet Group Name| ecachesubnetgroup | |
| Subnet Group Description | Subnet group for XKCD apps ElastiCache Redis Storage.| |
| Subnet Group VPC ID | Default VPC ID | You can choose your own VPC. |
| Subnet Group Subnets | 2c, 2a, 2b  | Select subnets for your VPC. |
| Subnet Group AZ Placement | No preference| |
| Security Group | XKCDAppElastiCacheSecurityGroup | |
| Encryption-at-Rest | True | |
| Encryption Key | Default | |
| Encryption in transit | True | |
| Access Control Option | No Access | |
</details>
<details>
  <summary><b> Engine and Location  </b></summary>

![ElastiCache: Engine and Location](assets/aws/ecache_create_1.png)
</details>
<details>
  <summary><b> Redis Settings  </b></summary>

![ElastiCache:  Redis Settings](assets/aws/ecache_create_2.png)

</details>
<details>
  <summary><b> Advanced Redis Settings </b></summary>

![ElastiCache: Advanced Redis Settings](assets/aws/ecache_create_3.png)

</details>
<details>
  <summary><b> Security  </b></summary>

![ElastiCache: Security](assets/aws/ecache_create_4.png)
</details>


#### adding endpoint to parameterstore
Go to `Parameter Store` under `AWS Systems Manager` and add `ELASTICACHE_ENDPOINT` without port `:6379` to parameter store.



| Setting | Option | 
| --| --| --|
| Name | xkcdapp/test/ELASTICACHE_ENDPOINT | 
| Description | xkcd app ElastiCache Redis Endpoint | 
| Tier | Standard |
| Type | SecureString |
| KMS key source | My Current Account |
| KMS Key ID | alias/aws/ssm |
| Value | xkcdappredis.xxxxx.yyyy.rrrr.cache.amazonaws.com  | 



#### installing [django-redis](https://github.com/jazzband/django-redis) package
```bash
# be sure to be in venv virtuall environment
pip install django-redis
```
#### updating Django settings to use Redis as Session Storage

```python
# xkcd_app/xkcd_app/settings.py
# ELASTICACHE_ENDPOINT without the port 
ELASTICACHE_ENDPOINT = ssm.get_parameter(Name=prefixenv + "ELASTICACHE_ENDPOINT", WithDecryption=True)['Parameter']['Value']
CACHE_LOCATION =  f"redis://{ELASTICACHE_ENDPOINT}/0"
CACHES = {
    "default": {
        "BACKEND": "django_redis.cache.RedisCache",
        "LOCATION": CACHE_LOCATION,
        "OPTIONS": {
            "CLIENT_CLASS": "django_redis.client.DefaultClient",
        }
    }
}
#Use the redis as Session storage as well.
SESSION_ENGINE = "django.contrib.sessions.backends.cache"
SESSION_CACHE_ALIAS = "default"
```

### Elastic Container Registry
Go to `Repositories` under `Elastic Container Registry` and click on the Create Repository button. Give your ECR repository a name and click create.

![Elastic Container Registry Creation](assets/aws/ecr_create_1.png)

#### uploading XKCD Apps Docker Image to ECR
Go to detail page of your repository and click on the `View Push Commands` on the upper right. This will give you `login`, `build`, `tag` and `push` commands specific to your repository.

```bash
# get credentials to ECR Repo
aws ecr get-login-password --region eu-west-2 | docker login --username AWS --password-stdin 12345678912.dkr.ecr.eu-west-2.amazonaws.com

#build your image
docker build -t xckdapp .

# tag it as the latest
docker tag xckdapp:latest 12345678912.dkr.ecr.eu-west-2.amazonaws.com/xckdapp:latest

# push to ECR
docker push 12345678912.dkr.ecr.eu-west-2.amazonaws.com/xckdapp:latest

```
### Elastic Container Service
#### ExecutionRole, Security Group

Go to `Role` under `IAM` and click on create Role button. Attach policies below:
1. AmazonECSTaskExecutionRolePolicy (aws managed)
2. SystemManagerParameterStoreFullAccess (custom)

![ECS Task Role Creation](assets/aws/ecs_task_role_create.png)

#### create security group

![](assets/aws/ecs_security_group.png)
| Setting | Option |
|-- |-- |
| Name | XKCDAppECSSecurityGroup |
| Description | XKCD Apps security group, allows container ports |
| VPC | Select your VPC, or use the default one. |
| Inbound Rules | Type: `CustomTCP`, Port Range: `80`, Source: `Anywhere` |
| Inbound Rules | Type: `CustomTCP`, Port Range: `8000`, Source: `Anywhere` |
| Outbound Rules | Type: `All Trafic`, Destination: `Anywhere` |


#### create a task definition
Go to `Task Definitions` under `Elastic Container Service` and create task definition.

![](assets/aws/ecs_task_def_1.png)
![](assets/aws/ecs_task_def_2.png)
![](assets/aws/ecs_task_def_container.png)


#### create cluster service
Go to default cluster
![](assets/aws/ecs_service_create.png)
![](assets/aws/ecs_service_security_group.png)



#### creating fargate flee

### Elastic Load Balancing
#### Security Group
#### creation

### Route53
### updating security groups
--------
- parameter store + parameterstore Role (seanjziegler)
- database to aws rds, sec group open
- session on redis
- 


- dockerize - upload to ecr 
- ecs - hey benchmark - autoscaling group
- elb
- acm certificate

## Serverful approach
- We serve the clothing classification model with Tensorflow Serving on Kubernetes.
- Kubernetes is a container orchestation platform (place where we can deploy Docker containers). 
- It takes cares of exposing these containers as a web service and scales these services up and down as the amount of requests we receive changes. 

# Plan
- First, we convert the Keras model into the special format used by Tensorflow Serving. 
- Then we use Tensorflow Serving to run the model locally.
- After that, we create a service for preprocessing images and communicating with Tensorflow Serving. 
- Finally, we deploy both the model and the preprocessing service with Kubernetes. 

# TensorFlow Serving 
- Is a system design for serving Tensorflow models. 
- AWS Lambda is great for experiment and dealing with small amount of images - fewer than one million per day. But when we grow pst that amount AWS Lambda becomes expensive, then deploying models with Kubernetes and TF Serving is better option.
- Focuses on only one thing - serving the model. It expects data already prepared (images already preprocessed).

## Serving Architecture
- Gateway: The preprocessing part. It gets the URL for which we need to make the prediction, prepares it and sends it further to the model. We will use Flask for creating this service. 
- Model: The part with the actual model. We use TF Serving for this. 
- Gateway spends a lot of time downloading the images in addition to doing preprocessing. It doesn't need a powerful computer for that. 
- The TF Serving component requires a more powerful machine, often with a GPU it would be wasteful to use this powerful machine for downloading images.
- We might require many gateway instances and only a few TF Serving instances. By separating them into different components, we can scale each independently. 

## Gateway Service

- Take the URL of an image in the rerquest 
- Download the image, preprocess it, and convert it to a Numpy array. 
- Convert the Numpy array to protobuf, and use gRPC to communicate with TF Serving. 
- Postprocess the results -- convert the raw list with numbers to human-understandable form. 

## Running TF-Serving locally

Get the model from Chapter 7:

```zsh
wget https://github.com/alexeygrigorev/mlbookcamp-code/releases/download/chapter7-model/xception_v4_large_08_0.894.h5
```

Convert it to `saved_model`:

```zsh
python convert.py
```

We need to know a few things: 

- Model signature: serving_default
- The name of the input layer: input_8
- The name of the output layer: dense_7

```zsh
saved_model_cli show --dir clothing-model --all
```

Run TF-Serving with Docker:

```zsh
docker run -it --rm \
    -p 8500:8500 \
    -v "$(pwd)/clothing-model:/models/clothing-model/1" \
    -e MODEL_NAME=clothing-model \
    tensorflow/serving:2.3.0
```

for Mac M1: 

```zsh
docker run -it --rm \                                                                                            
    -p 8500:8500 \
    -v "$(pwd)/clothing-model:/models/clothing-model/1" \
    -e MODEL_NAME=clothing-model \
    emacski/tensorflow-serving:latest-linux_arm64
```

Now open [09-image-preparation.ipynb](09-image-preparation.ipynb) and
execute the code there to test it

## Creating a Kubernetes cluster on AWS

![alt text](https://github.com/pablonoras/clothes-recognition-kubernetes)

- We use EKS (elastic kubernetes service), also there is GKE from google and AKS from azure. 
- We need to use 3 command-line tools: awscli (Manages AWS resources) , eksctl (Manages EKS clusters) , kubectl (Manages resources in a Kubernetes cluster)

1) Create the cluster.yaml file with the cluster configuration 
2) Run: ```eksctl create cluster -f cluster.yaml ```
3) With this configuration, we create a cluster with Kubernetes version 1.18 deployed in the eu-west-1 region. The name of the cluster is ml-bookcamp-eks. 
* EKS is not covered by the AWS free tier
4) Now we need to configure kubectl to be able to access it, for aws we use the awscli by running: ``` awseks --region eu-west-1 update-kubeconfig --name ml-bookcamp-eks```
5) This command should generate a kubectl config file in ~/.kube/config, we check it by running: ``` kubectl get service ```
6) We check that the connection works and then we are able to deploy a service. 
7) Prepare de Docker images and publish our docker images into ecr (doker registry of aws):
 - create a registry with: ```aws ecr create-repository --repository-name model-serving``` , it returns a path and we should save it. 
 - create our tf-serving.dockerfile and build it: ```docker build -t tf-serving-clothing-model -f tf-serving.dockerfile .```
 - ```$(aws ecr get-login --no-include-email)``` (we need to authenticate to awscli)
 - tag the image with the remote uri and push to ecr: 
    ```
    REGION=eu-west-1
    ACCOUNT=XXXXXXXXXXXX
    REMOTE_NAME=${ACCOUNT}.dkr.ecr.${REGION}.amazonaws.com/model-serving:${IMAGE_SERVING_LOCAL}
    docker tag  ${REMOTE_NAME}
    docker push ${REMOTE_NAME} 
   ```
8) To deploy an application to Kubernetes, we need to configure a deployment (specifies how the pods of this deployment will look) and a service (specifies how to access the service and how the service connects to the pods).
   - For that we create the files tf-serving-clothing-model-deployment.yaml

9) We create a kubernetes object by running: ```kubectl apply -f tf-serving-clothing-model-deployment.yaml``` . To verify its working: ```kubectl get deployments``` and ```kubectl get pods```

10) We need to create a service for this deployment, for that we create the config file ```tf-serving-clothing-model-service.yaml```

11) We applied ```kubectl apply -f tf-serving-clothing-model-service.yaml``` . To verify: ```kubectl get services```. We have an url for this service. 

12) We've created a deployment for TF Serving as well as a service. Now we create a deployment for Gateway like previously. We create the file serving-gateway-deployment.yaml and apply it.

13) We create a service for Gateway, this is different from the service we created for TF Serving, it needs to be publicly accesible. For that we use the service LoadBalancer. In the case of aws it uses ELB (elastic load balancer). We create serving-gateway-service.yaml and apply it.

14) To see the external url of the service we can use: ```kubectl describe service serving-gateway```, and that's all!

* If you finished experimenting with EKS, don't forget to shut down the cluster, if not you will pay for it, even if you are not using it."
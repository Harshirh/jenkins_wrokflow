# E-Commerce Website CI/CD

This repository packages the existing static e-commerce website in Nginx and provides a Jenkins pipeline to build and test a Docker image, publish it to Docker Hub, then deploy it to Kubernetes. The existing HTML, CSS, images, links, and page behavior are served as-is.

## Technologies and architecture

- Website: HTML, CSS, existing image assets
- Web server and container: Nginx Alpine, Docker
- CI/CD: Jenkins Pipeline (Windows agent commands)
- Deployment: Kubernetes Deployment (2 replicas) and NodePort Service
- Registry: Docker Hub

GitHub push or manual Jenkins build → checkout → Docker build → HTTP smoke checks → Docker Hub push → Kubernetes rollout → rollout and service checks.

## Project structure

```text
images/                 Existing website image assets
Account.html            Account page
cart.html               Cart page
index.html              Home page
product.html            Product listing
productdetail.html      Product detail
style.css               Existing stylesheet
Dockerfile              Nginx Alpine image definition
.dockerignore           Docker build context exclusions
Jenkinsfile             Windows batch based CI/CD pipeline
k8s/deployment.yaml     Two replica web deployment and HTTP probes
k8s/service.yaml        NodePort service on port 30080
README.md               Setup and operating instructions
```

The Docker image copies all root HTML files, `style.css`, and `images/` into `/usr/share/nginx/html`. The pages use `/images/...` URLs, which resolve from this Nginx document root.

## Prerequisites

- Docker Desktop for Windows, with the Linux container engine running
- Docker Desktop Kubernetes enabled for local deployment
- `kubectl` installed and configured with the `docker-desktop` context
- A GitHub repository containing this project
- Jenkins with Pipeline, GitHub integration, and Credentials Binding plugins
- A Windows Jenkins agent with Git, Docker CLI/daemon access, `kubectl`, and `curl.exe` on `PATH`
- A Docker Hub account and a **public** repository named `ecommerce-app` (or configure a Kubernetes registry pull secret if keeping it private)

Jenkins is not part of this repository. A Jenkins service/controller and an online Windows agent must be set up separately. The pipeline intentionally checks that its Kubernetes context is `docker-desktop` before deploying; change that guard if the agent is configured for another cluster.

## Docker: local build and smoke test (PowerShell)

Start Docker Desktop and wait for its Linux engine to report ready. Run these commands from the project root:

```powershell
docker version
docker build -t ecommerce-app:local .
docker run --rm -d --name ecommerce-local -p 8080:80 ecommerce-app:local
try {
    $pages = @('index.html', 'product.html', 'productdetail.html', 'cart.html', 'Account.html', 'style.css', 'images/logo.png', 'images/product-1.jpg')
    foreach ($page in $pages) {
        $response = Invoke-WebRequest -Uri "http://localhost:8080/$page" -UseBasicParsing
        if ($response.StatusCode -ne 200) { throw "Request failed: $page" }
    }
    'All page and asset requests returned HTTP 200.'
} finally {
    docker rm -f ecommerce-local
}
```

Open <http://localhost:8080> to view the site. The smoke test uses `finally` to remove its temporary container even if a request fails.

## Docker Hub

Create a Docker Hub repository named `ecommerce-app`. The deployment manifest and pipeline use `YOUR_DOCKERHUB_USERNAME/ecommerce-app`; Jenkins substitutes the username stored in its credential. The Kubernetes image is tagged with the Jenkins build number and commit, as well as `latest`. Kubernetes deploys the unique build tag to ensure a pushed update causes a rollout.

For a manual PowerShell publish, set your username and authenticate interactively (Docker prompts for a token/password; do not put it in a command or commit it):

```powershell
$dockerHubUsername = 'YOUR_DOCKERHUB_USERNAME'
$tag = 'manual'
docker login --username $dockerHubUsername
docker build -t "$dockerHubUsername/ecommerce-app:$tag" -t "$dockerHubUsername/ecommerce-app:latest" .
docker push "$dockerHubUsername/ecommerce-app:$tag"
docker push "$dockerHubUsername/ecommerce-app:latest"
```

Use a Docker Hub access token for automation. Never store it in this repository.

## Kubernetes: Docker Desktop

In Docker Desktop, enable Kubernetes and confirm the cluster is ready. Then run:

```powershell
kubectl config current-context
kubectl cluster-info
$dockerHubUsername = 'YOUR_DOCKERHUB_USERNAME'
kubectl apply -f k8s/deployment.yaml
kubectl apply -f k8s/service.yaml
kubectl set image deployment/ecommerce-app ecommerce-app="$dockerHubUsername/ecommerce-app:latest"
kubectl rollout status deployment/ecommerce-app --timeout=180s
kubectl get pods -l app=ecommerce-app -o wide
kubectl get service ecommerce-app
```

The checked-in deployment image is a placeholder. Replace it using `kubectl set image` as above, or let Jenkins do so after applying the manifest. For a public Docker Hub repository, no pull secret is needed. The service exposes HTTP port 80 at NodePort 30080. On Docker Desktop, browse to <http://localhost:30080>.

To inspect problems, use `kubectl describe deployment ecommerce-app`, `kubectl describe pods -l app=ecommerce-app`, and `kubectl logs deployment/ecommerce-app`.

## Jenkins configuration

1. Create a Pipeline job (or Multibranch Pipeline) connected to the GitHub repository. Set the script path to `Jenkinsfile`. The `checkout scm` step uses that job's configured repository and branch, so no repository URL is embedded in source.
2. Use a Windows Jenkins agent with Git, Docker Desktop's Linux engine, `kubectl`, and `curl.exe` available to the Jenkins service account. Configure Docker Desktop Kubernetes for that same Windows account and verify `kubectl config current-context` returns `docker-desktop` when run as the agent.
3. In **Manage Jenkins → Credentials**, add a **Username with password** credential in the Jenkins (global) store with ID `dockerhub-credentials`. Use your Docker Hub username and a Docker Hub access token as its password. The pipeline reads these values through Jenkins credential binding; it does not save them in source.
4. Ensure the Docker Hub repository is public, or configure `imagePullSecrets` in the deployment before using a private repository.
5. For GitHub webhooks, install/enable the GitHub plugin, enable **GitHub hook trigger for GITScm polling** in the job, and add a GitHub repository webhook pointing to `https://YOUR_JENKINS_URL/github-webhook/` with content type `application/json`. Jenkins must be reachable by GitHub. The `githubPush()` trigger is also declared in the Jenkinsfile. Manual **Build Now** works without a webhook.

The pipeline stages are Checkout, Build, Test, Docker Hub Login, Push, Kubernetes Deployment, and Verification. It pushes both a unique build tag and `latest`; applies both manifests; sets the Deployment to the unique image tag; waits for rollout; and lists Pods and Service. A failed command fails its stage and the pipeline. The `docker-desktop` context guard prevents accidental deployment to a different cluster.

## Troubleshooting

- **Docker cannot connect to the daemon:** Start Docker Desktop, select the Linux container engine, and wait for `docker version` to show both Client and Server.
- **`docker build` cannot pull `nginx:alpine`:** Check Docker Desktop networking and registry access, then retry after the daemon is ready.
- **Jenkins cannot run Docker or kubectl:** Install the Windows CLI tools and configure `PATH` and Docker/Kubernetes access for the Jenkins service account, not only your interactive account.
- **Docker Hub login or push fails:** Verify the Jenkins credential ID, username, access token, and repository permissions. Do not print or commit the token.
- **Pods show `ImagePullBackOff`:** Check the pushed image tag and repository visibility. Private images need a Kubernetes registry pull secret.
- **Rollout times out:** Run `kubectl describe pods -l app=ecommerce-app` and `kubectl get events --sort-by=.lastTimestamp` to find scheduling, pull, or probe errors.
- **Webhook does not trigger:** Confirm GitHub can reach the Jenkins webhook URL, the GitHub plugin and job trigger are enabled, and Jenkins logs show the request. Manual **Build Now** remains available.
- **Port 30080 is unavailable:** Check that Docker Desktop Kubernetes is running and that another local process is not using that port.

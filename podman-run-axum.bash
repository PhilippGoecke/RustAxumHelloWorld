podman build --no-cache --rm --file Containerfile --tag axum:demo .
podman run --interactive --tty --publish 5000:5000 axum:demo
echo "browse http://localhost:5000/?name=Test"

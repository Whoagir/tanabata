$env:CGO_ENABLED="1"
$env:CC="gcc"
$env:GOOS="windows"
$env:GOARCH="amd64"
go build -tags raylib_static -ldflags="-s -w" -o game.exe cmd/game/main.go

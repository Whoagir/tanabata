# reset_env.ps1
$env:GOROOT = ""
$env:GOPATH = "C:\go_project\go-tower-defense\gopath"
$env:GOCACHE = "C:\go_project\go-tower-defense\gocache"
$env:GOMODCACHE = "C:\go_project\go-tower-defense\gocache\pkg\mod"
$env:GO111MODULE = "on"

# Создай структуру папок
New-Item -ItemType Directory -Path $env:GOPATH -Force
New-Item -ItemType Directory -Path $env:GOCACHE -Force
New-Item -ItemType Directory -Path $env:GOMODCACHE -Force

# Очисти кэш
go clean -cache
go clean -modcache

# Пересоздай go.mod
Remove-Item go.mod -ErrorAction SilentlyContinue
Remove-Item go.sum -ErrorAction SilentlyContinue
go mod init go-tower-defense

# Установи зависимости локально
go get github.com/hajimehoshi/ebiten/v2@latest
go get golang.org/x/image@latest
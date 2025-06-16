// cmd/game/main.go
package main

import (
	"go-tower-defense/internal/config"
	"go-tower-defense/internal/state"
	"log"
	"math/rand"
	"net/http"
	_ "net/http/pprof"
	"time"

	"github.com/hajimehoshi/ebiten/v2"
)

const startFromGame = true // true — начинать с игры, false — с меню

type AppGame struct {
	stateMachine   *state.StateMachine
	lastUpdateTime time.Time
}

func (a *AppGame) Update() error {
	now := time.Now()
	deltaTime := now.Sub(a.lastUpdateTime).Seconds()
	if deltaTime > config.MaxDeltaTime {
		deltaTime = config.MaxDeltaTime
	}
	a.lastUpdateTime = now
	a.stateMachine.Update(deltaTime)
	return nil
}

func (a *AppGame) Draw(screen *ebiten.Image) {
	a.stateMachine.Draw(screen)
}

func (a *AppGame) Layout(outsideWidth, outsideHeight int) (int, int) {
	return config.ScreenWidth, config.ScreenHeight
}

func main() {
	go func() {
		log.Println(http.ListenAndServe("localhost:6060", nil))
	}()
	rand.Seed(time.Now().UnixNano())
	sm := state.NewStateMachine() // Создаём машину состояний
	if startFromGame {
		sm.SetState(state.NewGameState(sm)) // Устанавливаем состояние игры
	} else {
		sm.SetState(state.NewMenuState(sm)) // Устанавливаем состояние меню
	}
	app := &AppGame{
		stateMachine:   sm,
		lastUpdateTime: time.Now(),
	}
	ebiten.SetWindowSize(config.ScreenWidth, config.ScreenHeight)
	ebiten.SetWindowTitle("Hexagonal Map")
	if err := ebiten.RunGame(app); err != nil {
		log.Fatal(err)
	}
}

package assets

import (
	"fmt"
	"go-tower-defense/internal/defs"
	"log"
	"os"
	"path/filepath"

	rl "github.com/gen2brain/raylib-go/raylib"
)

// ModelManager управляет загрузкой, кэшированием и выгрузкой 3D-моделей.
type ModelManager struct {
	models     map[string]rl.Model
	wireModels map[string]rl.Model
}

// NewModelManager создает новый экземпляр ModelManager.
func NewModelManager() *ModelManager {
	return &ModelManager{
		models:     make(map[string]rl.Model),
		wireModels: make(map[string]rl.Model),
	}
}

// loadSingleModel безопасно загружает одну модель и ее текстуру.
func (m *ModelManager) loadSingleModel(id string, def *defs.TowerDefinition) {
	defer func() {
		if r := recover(); r != nil {
			log.Printf("FATAL: Raylib panicked while loading model for '%s'. This model is likely corrupt. Skipping. Panic: %v", id, r)
		}
	}()

	if def.Type == defs.TowerTypeMiner {
		return
	}
	if _, ok := m.models[id]; ok {
		return
	}

	modelPath := filepath.Join("assets", "models", fmt.Sprintf("%s.obj", id))
	model := rl.LoadModel(modelPath)

	if model.MeshCount == 0 {
		log.Printf("WARNING: Failed to load model for %s from path %s. It might be invalid or empty.", id, modelPath)
		return
	}

	// По соглашению, ищем текстуру с таким же ID в папке textures
	texturePath := filepath.Join("assets", "textures", fmt.Sprintf("%s.png", id))
	// Проверяем существование файла с помощью стандартной библиотеки Go
	if _, err := os.Stat(texturePath); err == nil {
		texture := rl.LoadTexture(texturePath)
		if texture.ID > 0 {
			// Применяем текстуру к первому материалу модели.
			// rl.SetMaterialTexture - это правильный способ сделать это.
			// rl.MapDiffuse - это стандартный слот для основной текстуры (цвета).
			rl.SetMaterialTexture(model.Materials, rl.MapDiffuse, texture)
			log.Printf("Successfully applied texture %s to model %s", texturePath, id)
		} else {
			log.Printf("WARNING: Failed to load texture for model %s from %s", id, texturePath)
		}
	}

	m.models[id] = model
	m.wireModels[id] = model // Каркасная модель может быть той же
	log.Printf("Successfully loaded model for %s", id)
}

// LoadTowerModels загружает все модели башен.
func (m *ModelManager) LoadTowerModels(towerDefs map[string]*defs.TowerDefinition) {
	for id, def := range towerDefs {
		m.loadSingleModel(id, def)
	}
}

// Cleanup выгружает все загруженные модели.
func (m *ModelManager) Cleanup() {
	for id, model := range m.models {
		rl.UnloadModel(model)
		delete(m.models, id)
	}
	// Поскольку wireModels теперь ссылаются на те же модели, что и models,
	// нет необходимости вызывать UnloadModel для них еще раз. Просто очищаем мапу.
	m.wireModels = make(map[string]rl.Model)
	log.Println("All models unloaded.")
}

// ReloadTowerModels выгружает все модели и загружает их заново.
func (m *ModelManager) ReloadTowerModels(towerDefs map[string]*defs.TowerDefinition) {
	log.Println("Reloading all tower models...")
	m.Cleanup()
	m.LoadTowerModels(towerDefs)
	log.Println("All tower models reloaded.")
}

// GetModel возвращает основную модель по ID.
func (m *ModelManager) GetModel(id string) (rl.Model, bool) {
	model, ok := m.models[id]
	return model, ok
}

// GetWireModel возвращает каркасную модель по ID.
func (m *ModelManager) GetWireModel(id string) (rl.Model, bool) {
	wireModel, ok := m.wireModels[id]
	return wireModel, ok
}
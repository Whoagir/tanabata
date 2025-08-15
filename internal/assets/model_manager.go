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
	models           map[string]rl.Model
	wireModels       map[string]rl.Model
	baseModels       map[string]rl.Model // Для оснований башен
	headModels       map[string]rl.Model // Для "голов" башен
	wireBaseModels   map[string]rl.Model
	wireHeadModels   map[string]rl.Model
	baseModelHeights map[string]float32 // Кэшированные высоты базовых моделей
}

// NewModelManager создает новый экземпляр ModelManager.
func NewModelManager() *ModelManager {
	return &ModelManager{
		models:           make(map[string]rl.Model),
		wireModels:       make(map[string]rl.Model),
		baseModels:       make(map[string]rl.Model),
		headModels:       make(map[string]rl.Model),
		wireBaseModels:   make(map[string]rl.Model),
		wireHeadModels:   make(map[string]rl.Model),
		baseModelHeights: make(map[string]float32),
	}
}

// loadSingleModel безопасно загружает одну модель и ее текстуру.
func (m *ModelManager) loadSingleModel(id string, def *defs.TowerDefinition) {
	defer func() {
		if r := recover(); r != nil {
			log.Printf("FATAL: Raylib panicked while loading model for '%s'. This model is likely corrupt. Skipping. Panic: %v", id, r)
		}
	}()

	if _, ok := m.models[id]; ok {
		return
	}

	modelPath := filepath.Join("assets", "models", fmt.Sprintf("%s.obj", id))
	if _, err := os.Stat(modelPath); os.IsNotExist(err) {
		return // Файла нет, пропускаем
	}

	model := rl.LoadModel(modelPath)

	if model.MeshCount == 0 {
		log.Printf("WARNING: Failed to load model for %s from path %s. It might be invalid or empty.", id, modelPath)
		return
	}

	texturePath := filepath.Join("assets", "textures", fmt.Sprintf("%s.png", id))
	if _, err := os.Stat(texturePath); err == nil {
		texture := rl.LoadTexture(texturePath)
		if texture.ID > 0 {
			rl.SetMaterialTexture(model.Materials, rl.MapDiffuse, texture)
			log.Printf("Successfully applied texture %s to model %s", texturePath, id)
		} else {
			log.Printf("WARNING: Failed to load texture for model %s from %s", id, texturePath)
		}
	}

	m.models[id] = model
	m.wireModels[id] = model
	log.Printf("Successfully loaded model for %s", id)
}

// LoadTowerModels загружает все модели башен, включая составные.
func (m *ModelManager) LoadTowerModels(towerDefs map[string]*defs.TowerDefinition) {
	for id, def := range towerDefs {
		baseLoaded, headLoaded := m.tryLoadCompositeModel(id)
		if !baseLoaded || !headLoaded {
			m.loadSingleModel(id, def)
		}
	}
}

// tryLoadCompositeModel пытается загрузить модели _BASE и _HEAD для данного ID.
func (m *ModelManager) tryLoadCompositeModel(id string) (bool, bool) {
	basePath := filepath.Join("assets", "models", fmt.Sprintf("%s_BASE.obj", id))
	headPath := filepath.Join("assets", "models", fmt.Sprintf("%s_HEAD.obj", id))

	if _, err := os.Stat(basePath); os.IsNotExist(err) {
		return false, false
	}
	if _, err := os.Stat(headPath); os.IsNotExist(err) {
		return false, false
	}

	baseModel := rl.LoadModel(basePath)
	headModel := rl.LoadModel(headPath)

	if baseModel.MeshCount > 0 && headModel.MeshCount > 0 {
		// Вычисляем и сохраняем точную высоту базовой модели
		bbox := rl.GetModelBoundingBox(baseModel)
		height := bbox.Max.Y - bbox.Min.Y
		m.baseModelHeights[id] = height
		log.Printf("Calculated and stored base height for %s: %f", id, height)

		// Вычисляем и логируем размеры модели головы
		headBBox := rl.GetModelBoundingBox(headModel)
		headWidth := headBBox.Max.X - headBBox.Min.X
		headHeight := headBBox.Max.Y - headBBox.Min.Y
		headLength := headBBox.Max.Z - headBBox.Min.Z
		log.Printf("Dimensions for head model %s: Width=%.2f, Height=%.2f, Length=%.2f", id, headWidth, headHeight, headLength)

		m.baseModels[id] = baseModel
		m.headModels[id] = headModel
		m.wireBaseModels[id] = baseModel
		m.wireHeadModels[id] = headModel
		log.Printf("Successfully loaded composite model for %s", id)
		return true, true
	}

	if baseModel.MeshCount > 0 {
		rl.UnloadModel(baseModel)
	}
	if headModel.MeshCount > 0 {
		rl.UnloadModel(headModel)
	}

	log.Printf("WARNING: Found composite model files for %s, but failed to load them.", id)
	return false, false
}

// Cleanup выгружает все загруженные модели.
func (m *ModelManager) Cleanup() {
	for id, model := range m.models {
		rl.UnloadModel(model)
		delete(m.models, id)
	}
	for id, model := range m.baseModels {
		rl.UnloadModel(model)
		delete(m.baseModels, id)
	}
	for id, model := range m.headModels {
		rl.UnloadModel(model)
		delete(m.headModels, id)
	}
	m.wireModels = make(map[string]rl.Model)
	m.wireBaseModels = make(map[string]rl.Model)
	m.wireHeadModels = make(map[string]rl.Model)
	m.baseModelHeights = make(map[string]float32) // Очищаем кэш высот
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

func (m *ModelManager) GetBaseModel(id string) (rl.Model, bool) {
	model, ok := m.baseModels[id]
	return model, ok
}

func (m *ModelManager) GetWireBaseModel(id string) (rl.Model, bool) {
	model, ok := m.wireBaseModels[id]
	return model, ok
}

func (m *ModelManager) GetHeadModel(id string) (rl.Model, bool) {
	model, ok := m.headModels[id]
	return model, ok
}

func (m *ModelManager) GetWireHeadModel(id string) (rl.Model, bool) {
	model, ok := m.wireHeadModels[id]
	return model, ok
}

// GetBaseModelHeight возвращает сохраненную высоту базовой модели.
func (m *ModelManager) GetBaseModelHeight(id string) (float32, bool) {
	height, ok := m.baseModelHeights[id]
	return height, ok
}
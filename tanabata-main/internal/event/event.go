// internal/event/event.go
package event

// EventType — тип события
type EventType string

// Event — структура события
type Event struct {
	Type EventType
	Data interface{} // Данные события, если нужны
}

// Listener — интерфейс для подписчиков на события
type Listener interface {
	OnEvent(event Event)
}

// Dispatcher — диспетчер событий
type Dispatcher struct {
	listeners map[EventType][]Listener
}

// NewDispatcher — создаёт новый диспетчер
func NewDispatcher() *Dispatcher {
	return &Dispatcher{
		listeners: make(map[EventType][]Listener),
	}
}

// Subscribe — подписка на событие
func (d *Dispatcher) Subscribe(eventType EventType, listener Listener) {
	d.listeners[eventType] = append(d.listeners[eventType], listener)
}

// Unsubscribe — отписка от события
func (d *Dispatcher) Unsubscribe(eventType EventType, listener Listener) {
	if listeners, exists := d.listeners[eventType]; exists {
		for i, l := range listeners {
			if l == listener {
				d.listeners[eventType] = append(listeners[:i], listeners[i+1:]...)
				break
			}
		}
	}
}

// Dispatch — отправка события всем подписчикам
func (d *Dispatcher) Dispatch(event Event) {
	if listeners, exists := d.listeners[event.Type]; exists {
		for _, listener := range listeners {
			listener.OnEvent(event)
		}
	}
}

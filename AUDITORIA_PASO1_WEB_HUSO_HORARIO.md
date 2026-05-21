# PASO 1: Corrección de Huso Horario - Portal Web

**Archivo:** `web_gestiongente/src/services/schedules.js`

## Cambio 1: `assignScheduleToEmployees` (línea ~69)

```javascript
// ANTES (bug - usa UTC):
export const assignScheduleToEmployees = async (employeeIds, scheduleId, assignedById, notes = null) => {
  const today = new Date().toISOString().split('T')[0]

// DESPUÉS (corregido - hora local Perú):
export const assignScheduleToEmployees = async (employeeIds, scheduleId, assignedById, notes = null) => {
  const today = new Date().toLocaleDateString('sv-SE', { timeZone: 'America/Lima' })
```

## Cambio 2: `removeScheduleAssignment` (línea ~138)

```javascript
// ANTES (bug - usa UTC):
export const removeScheduleAssignment = async (assignmentId) => {
  const today = new Date().toISOString().split('T')[0]

// DESPUÉS (corregido - hora local Perú):
export const removeScheduleAssignment = async (assignmentId) => {
  const today = new Date().toLocaleDateString('sv-SE', { timeZone: 'America/Lima' })
```

> Realizar estos cambios en el repo `web_gestiongente` y redesplegar el portal web.

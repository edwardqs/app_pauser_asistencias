import { createClient } from 'npm:@supabase/supabase-js@2'
import admin from 'npm:firebase-admin@12'

const supabaseUrl = Deno.env.get('SUPABASE_URL')!
const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!

const REMINDER_OFFSET_MINUTES = 15

function getFirebaseApp() {
  if (admin.apps.length > 0) return admin.apps[0]!

  const serviceAccountRaw = Deno.env.get('FIREBASE_SERVICE_ACCOUNT')
  if (!serviceAccountRaw) {
    throw new Error('FIREBASE_SERVICE_ACCOUNT no está configurado')
  }

  const serviceAccount = JSON.parse(serviceAccountRaw)
  return admin.initializeApp({
    credential: admin.credential.cert(serviceAccount),
  })
}

async function loadAttendanceData(supabase: any, today: string) {
  const { data, error } = await supabase
    .from('employee_schedule_assignments')
    .select(`
      employee_id,
      valid_from,
      valid_to,
      schedule:schedule_id (
        id,
        name,
        check_in_time,
        check_out_time,
        shift,
        work_days,
        schedule_type,
        is_active
      )
    `)
    .lte('valid_from', today)
    .or(`valid_to.is.null,valid_to.gte.${today}`)

  if (error) throw new Error(`Error cargando asignaciones: ${error.message}`)
  return data ?? []
}

async function loadAttendance(supabase: any, employeeId: string, date: string) {
  const { data, error } = await supabase
    .from('attendance')
    .select('id, work_date, check_in, check_out, shift, record_type')
    .eq('employee_id', employeeId)
    .eq('work_date', date)

  if (error) throw new Error(`Error cargando asistencia: ${error.message}`)
  return data ?? []
}

async function loadDevices(supabase: any, employeeId: string) {
  const { data, error } = await supabase
    .from('push_devices')
    .select('token, platform')
    .eq('employee_id', employeeId)

  if (error) throw new Error(`Error cargando dispositivos: ${error.message}`)
  return data ?? []
}

async function markDelivery(
  supabase: any,
  employeeId: string,
  workDate: string,
  scheduleId: string,
  shift: string,
  kind: string,
) {
  const { error } = await supabase.from('attendance_notification_deliveries').insert({
    employee_id: employeeId,
    work_date: workDate,
    schedule_id: scheduleId,
    shift,
    kind,
  })
  if (error) throw new Error(`Error registrando entrega: ${error.message}`)
}

async function alreadyDelivered(
  supabase: any,
  employeeId: string,
  workDate: string,
  scheduleId: string,
  shift: string,
  kind: string,
) {
  const { data, error } = await supabase
    .from('attendance_notification_deliveries')
    .select('id')
    .eq('employee_id', employeeId)
    .eq('work_date', workDate)
    .eq('schedule_id', scheduleId)
    .eq('shift', shift)
    .eq('kind', kind)
    .maybeSingle()

  if (error) throw new Error(`Error consultando entregas: ${error.message}`)
  return data != null
}

async function sendPush(tokens: string[], title: string, body: string, data: Record<string, string>) {
  const app = getFirebaseApp()
  const messaging = admin.messaging(app)

  const results = []
  for (const token of tokens) {
    try {
      const message = {
        token,
        notification: { title, body },
        data,
        android: {
          priority: 'high' as const,
          notification: {
            clickAction: 'FLUTTER_NOTIFICATION_CLICK',
            channelId: 'attendance_reminders',
          },
        },
        apns: {
          payload: {
            aps: {
              sound: 'default',
              'content-available': 1,
            },
          },
        },
      }
      await messaging.send(message)
      results.push({ token: token.slice(0, 8), ok: true })
    } catch (e) {
      results.push({ token: token.slice(0, 8), ok: false, error: String(e) })
    }
  }
  return results
}

Deno.serve(async (req) => {
  try {
    const supabase = createClient(supabaseUrl, serviceRoleKey)

    const now = new Date()
    const nowPeru = new Date(now.toLocaleString('en-US', { timeZone: 'America/Lima' }))
    const today = nowPeru.toISOString().slice(0, 10)

    const assignments = await loadAttendanceData(supabase, today)
    const isodow = nowPeru.getDay() === 0 ? 7 : nowPeru.getDay()

    const notifications: { employeeId: string; title: string; body: string; data: Record<string, string> }[] = []

    for (const assignment of assignments) {
      const schedule = assignment.schedule
      if (!schedule || !schedule.is_active || schedule.schedule_type !== 'REGULAR') continue
      if (schedule.work_days && !schedule.work_days.includes(isodow)) continue

      const employeeId = assignment.employee_id
      const scheduleId = schedule.id
      const shift = schedule.shift ?? 'UNICO'

      const attendances = await loadAttendance(supabase, employeeId, today)
      const attended = attendances.find((a: any) => a.shift === shift && a.record_type === 'ASISTENCIA')

      const devices = await loadDevices(supabase, employeeId)
      const tokens = devices.map((d: any) => d.token)

      const [checkInHour, checkInMin] = (schedule.check_in_time ?? '07:00').split(':').map(Number)
      const checkInAt = new Date(nowPeru)
      checkInAt.setHours(checkInHour, checkInMin, 0, 0)
      const checkInReminder = new Date(checkInAt.getTime() - REMINDER_OFFSET_MINUTES * 60000)

      if (!attended && nowPeru.getTime() >= checkInReminder.getTime() && nowPeru.getTime() < checkInAt.getTime()) {
        if (!(await alreadyDelivered(supabase, employeeId, today, scheduleId, shift, 'CHECK_IN'))) {
          notifications.push({
            employeeId,
            title: 'Hora de marcar entrada',
            body: `Tu turno ${shift} (${schedule.name}) inicia a las ${schedule.check_in_time.slice(0, 5)}.`,
            data: { type: 'CHECK_IN', shift, scheduleId, workDate: today },
          })
          await markDelivery(supabase, employeeId, today, scheduleId, shift, 'CHECK_IN')
        }
      }

      if (attended && !attended.check_out) {
        const [outHour, outMin] = (schedule.check_out_time ?? '18:00').split(':').map(Number)
        const outAt = new Date(nowPeru)
        outAt.setHours(outHour, outMin, 0, 0)
        if (schedule.check_out_time <= schedule.check_in_time) outAt.setDate(outAt.getDate() + 1)

        const checkOutReminderTime = new Date(outAt.getTime() - REMINDER_OFFSET_MINUTES * 60000)
        const checkOutReminder = nowPeru.getTime() >= checkOutReminderTime.getTime() && nowPeru.getTime() < outAt.getTime() ? checkOutReminderTime : null

        if (checkOutReminder) {
          if (!(await alreadyDelivered(supabase, employeeId, today, scheduleId, shift, 'CHECK_OUT'))) {
            notifications.push({
              employeeId,
              title: 'No olvides marcar tu salida',
              body: `Tu turno ${shift} termina a las ${schedule.check_out_time.slice(0, 5)}.`,
              data: { type: 'CHECK_OUT', shift, scheduleId, workDate: today },
            })
            await markDelivery(supabase, employeeId, today, scheduleId, shift, 'CHECK_OUT')
          }
        }
      }
    }

    let sentCount = 0
    const results: any[] = []
    for (const notification of notifications) {
      const devices = await loadDevices(supabase, notification.employeeId)
      const tokens = devices.map((d: any) => d.token)
      if (tokens.length === 0) continue
      const pushResults = await sendPush(tokens, notification.title, notification.body, notification.data)
      sentCount += pushResults.filter((r) => r.ok).length
      results.push(...pushResults)
    }

    return new Response(
      JSON.stringify({
        success: true,
        date: today,
        notifications: notifications.length,
        sentCount,
        results,
      }),
      { headers: { 'Content-Type': 'application/json' } },
    )
  } catch (e) {
    return new Response(
      JSON.stringify({ success: false, error: String(e) }),
      { status: 500, headers: { 'Content-Type': 'application/json' } },
    )
  }
})

-- -- Esquema de Base de Datos para App Asistencias Pauser --

-- 1. Tabla de Perfiles (Opcional pero recomendada para guardar DNI y Nombres)
-- Esta tabla extiende la tabla auth.users de Supabase
create table public.profiles (
  id uuid references auth.users on delete cascade not null primary key,
  dni text unique,
  full_name text,
  role text default 'operario', -- 'admin', 'operario'
  avatar_url text,
  created_at timestamp with time zone default timezone('utc'::text, now()) not null
);

-- Habilitar Row Level Security (RLS)
alter table public.profiles enable row level security;

-- Políticas de seguridad para profiles
create policy "Perfiles visibles por todos (o solo autenticados)" on public.profiles
  for select using (true);

create policy "Usuarios pueden actualizar su propio perfil" on public.profiles
  for update using (auth.uid() = id);

create policy "Usuarios pueden insertar su propio perfil" on public.profiles
  for insert with check (auth.uid() = id);

-- 2. Tabla de Registros de Asistencia
create table public.attendance_logs (
  id uuid default gen_random_uuid() primary key,
  user_id uuid references auth.users on delete cascade not null,
  check_in timestamp with time zone default timezone('utc'::text, now()) not null,
  check_out timestamp with time zone,
  date date default CURRENT_DATE,
  status text default 'presente', -- 'presente', 'tarde', 'ausente'
  location_lat double precision, -- Latitud GPS
  location_lng double precision, -- Longitud GPS
  device_info jsonb, -- Información del dispositivo
  notes text, -- Notas opcionales
  created_at timestamp with time zone default timezone('utc'::text, now()) not null
);

-- Habilitar RLS
alter table public.attendance_logs enable row level security;

-- Políticas para attendance_logs
create policy "Usuarios pueden ver sus propios registros" on public.attendance_logs
  for select using (auth.uid() = user_id);

create policy "Usuarios pueden registrar su entrada (insert)" on public.attendance_logs
  for insert with check (auth.uid() = user_id);

create policy "Usuarios pueden registrar su salida (update)" on public.attendance_logs
  for update using (auth.uid() = user_id);

-- NOTA SOBRE LOGIN CON DNI:
-- Supabase Auth utiliza Email/Password por defecto.
-- Para permitir login con DNI, la estrategia implementada en la App asume que
-- el email del usuario es: {DNI}@pauser.app
-- Ejemplo: Si el DNI es 12345678, el email será 12345678@pauser.app
-- Al registrar usuarios en el panel de Supabase, use este formato de email.

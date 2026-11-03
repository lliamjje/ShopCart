export class AppError extends Error {
  constructor(public readonly status: number, public readonly code: string, message: string) { super(message); }
}
export const unavailable = () => new AppError(503, 'DATABASE_UNAVAILABLE', 'Base de datos no disponible.');

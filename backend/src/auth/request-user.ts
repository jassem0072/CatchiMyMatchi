export type RequestUser = {
  sub: string;
  email: string;
  role: 'player' | 'scouter' | 'admin';
};

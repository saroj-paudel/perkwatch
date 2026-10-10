import type { Metadata } from 'next';
import './globals.css';

export const metadata: Metadata = {
  title: 'Perkwatch',
  description: 'Track credits and perks before they expire.',
};

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}

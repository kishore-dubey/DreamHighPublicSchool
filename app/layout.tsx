import type { Metadata } from 'next';
import './globals.css';

export const metadata: Metadata = {
  title: 'DreamHigh Public School | Waraseoni',
  description: 'A joyful, close-knit school in Waraseoni where children learn through fun, culture and curiosity.',
  openGraph: {
    title: 'DreamHigh Public School',
    description: 'Big dreams begin in happy classrooms. Joyful learning in Waraseoni, Madhya Pradesh.',
    images: [{ url: '/og.png', width: 1733, height: 909, alt: 'DreamHigh Public School — Big dreams begin in happy classrooms' }],
  },
  twitter: {
    card: 'summary_large_image',
    title: 'DreamHigh Public School',
    description: 'Big dreams begin in happy classrooms. Joyful learning in Waraseoni, Madhya Pradesh.',
    images: ['/og.png'],
  },
};

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return <html lang="en"><body>{children}</body></html>;
}

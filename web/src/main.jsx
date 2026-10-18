import { render } from 'preact';
import { App } from './app.jsx';
import './styles.css';

render(<App />, document.getElementById('app'));

if ('serviceWorker' in navigator && import.meta.env.PROD) {
  navigator.serviceWorker.register('/sw.js');
}

// Keep it feeling like an app: iOS can ignore user-scalable=no, so block pinch-zoom too.
document.addEventListener('gesturestart', (e) => e.preventDefault());

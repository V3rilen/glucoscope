import path from 'node:path';
import express from 'express';
import { Liquid } from 'liquidjs';
import routes from './routes/index.js';
import { notFound, errorHandler } from './middleware/errorHandler.js';

const rootDir = path.join(import.meta.dirname, '..');
const viewsDir = path.join(rootDir, 'views');
const isProduction = process.env.NODE_ENV === 'production';

const liquid = new Liquid({
  root: viewsDir,
  layouts: path.join(viewsDir, 'layouts'),
  partials: path.join(viewsDir, 'partials'),
  extname: '.liquid',
  outputEscape: 'escape',
  cache: isProduction,
});

const app = express();

app.engine('liquid', liquid.express());
app.set('views', viewsDir);
app.set('view engine', 'liquid');
app.disable('x-powered-by');
app.locals.siteName = 'Glucoscope';

// Cloudflare sits in front in production. Without this, Express sees plain
// HTTP from the proxy and refuses to set secure session cookies.
if (isProduction) app.set('trust proxy', 1);

app.use(express.static(path.join(rootDir, 'public')));
app.use(express.urlencoded({ extended: false }));

// Pages can contain health data, so Cloudflare and browsers must not store them.
app.use((req, res, next) => {
  res.set('Cache-Control', 'private, no-store');
  next();
});

app.use(routes);

app.use(notFound);
app.use(errorHandler);

export default app;

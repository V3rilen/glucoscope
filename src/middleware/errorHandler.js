export function notFound(req, res, next) {
  const err = new Error(`Not found: ${req.originalUrl}`);
  err.status = 404;
  next(err);
}

function publicMessage(status) {
  if (status === 404) return "We couldn't find that page.";
  if (status < 500) return "That request couldn't be processed.";
  return 'Something went wrong on our end. Please try again.';
}

// Express identifies error handlers by their four arguments, so next must stay.
export function errorHandler(err, req, res, next) {
  if (res.headersSent) return next(err);

  const status = err.status >= 400 && err.status < 600 ? err.status : 500;
  if (status >= 500) console.error(err);

  res.status(status).render('pages/error', {
    title: status === 404 ? 'Page not found' : 'Error',
    status,
    message: publicMessage(status),
    stack: process.env.NODE_ENV === 'production' ? null : err.stack,
  });
}

import app from './src/app.js';

const port = process.env.PORT || 3000;

app.listen(port, (err) => {
  if (err) throw err;
  console.log(`Glucoscope listening on port ${port}`);
});

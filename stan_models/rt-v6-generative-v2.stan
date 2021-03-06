// to do
// - bring the timing distribution into stan with the line list
// - do the convolution in stan as well
//   - this will make the dependent var a parameter
//   - https://www.youtube.com/watch?v=KOIudAB6vJ0
//   - or can i just round it s.t. i get an int? 

data {
  int timesteps; 
  int states;
  int cases[timesteps, states]; // raw
  vector[timesteps] p_observed; /// make this estimated 
  vector[timesteps] cum_p_observed; // not used
} 

transformed data {
  matrix[timesteps, timesteps] onsets_to_cases = rep_matrix(0, timesteps, timesteps);
  // matrix[timesteps, timesteps] onsets_to_cases;
  
  for(i in 1:timesteps) {
    onsets_to_cases[i:timesteps, i] = p_observed[1:(timesteps-(i-1))];
  }
  
}

parameters {
  real<lower=0> serial_interval;
  real<lower=0> step_size;
  matrix[timesteps-1, states] theta_steps;
  row_vector<lower=0>[states] initial_seed;
  vector<lower=0>[5] tau;
  matrix<lower=0>[timesteps-1, states] log_onsets_after_one;
  
}

transformed parameters {
  matrix[timesteps-1, states] theta;
  real<lower=0> gam;
  matrix[timesteps-1, states] rt;
  matrix[timesteps, states] log_onsets;
  matrix[timesteps, states] onsets;
  
  matrix<lower=0>[timesteps, states] expected_cases;
  

  for(s in 1:states) {
    theta[, s] = cumulative_sum(theta_steps[, s]);
  }
  
  log_onsets = append_row(initial_seed, log_onsets_after_one);
  onsets = exp(log_onsets);
  
  expected_cases = onsets_to_cases * onsets;
  
  
  gam = 1/serial_interval;
  rt = theta/gam + 1;
}

model {
  
  // https://epiforecasts.io/covid/
  // an uncertain serial interval with a mean of 4.7 days (95% CrI: 3.7, 6.0) 
  // and a standard deviation of 2.9 days (95% CrI: 1.9, 4.9) [7] .
  serial_interval ~ gamma(2.626635, 0.5588585);
  
  step_size ~ normal(0, tau[1])T[0, ];

  initial_seed ~ gamma(tau[2], tau[3]);
  
  tau ~ gamma(.5, .5);

  theta_steps[1, ] ~ normal(0, 1);
  to_vector(theta_steps[2:(timesteps-1), ]) ~ normal(0, step_size);
  
  for(s in 1:states) {
    log_onsets_after_one[1, s] ~ normal(initial_seed[s] + theta[1, s], tau[5]);
    for(t in 2:(timesteps-1)) {
      log_onsets_after_one[t, s] ~ normal(log_onsets_after_one[t-1, s] + theta[1, s], tau[5]);
    }
  }
  
  for(s in 1:states) {
    cases[, s] ~ neg_binomial_2(expected_cases[, s], tau[4]);
  } 
  
  
}

generated quantities {
  vector[(timesteps)*states] log_lik;
  matrix[timesteps, states] loglikm;

  for(s in 1:states) {
    for(t in 1:timesteps){
      loglikm[t, s] = poisson_lpmf(cases[t, s] | expected_cases[t, s]);  
    }
  } 
  
  
  log_lik = to_vector(loglikm);

}

